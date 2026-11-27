#!/usr/bin/env python3
# =============================================================================
# Project: ProEm - Open Source Protocol Emulator
# File: scripts/mutate.py
# Type: Script: mutation testing of the formal proofs (Yosys mutate + SymbiYosys)
# Author: Paul Vincent Bezzina
# Language: Python
# Description: Plants small faults in the RTL under each proof, one at a time, and checks that the proof catches them. A fault the
# proof misses is then compared with the original design to tell a real gap from a fault with no visible effect.
# =============================================================================
#
# Usage:  python3 scripts/mutate.py [proof ...] [-n N] [--depth D] [--seed S]
#   proof   name of a .sby in formal/ (default: every proof in PROOFS below)
#   -n N    mutations per proof (default 16)
#
# For each mutation:
#   1. Kill check: the proof's harness, with the mutation applied to the module under test, run as a bounded check (ABC bmc3) of
#      depth D. Helper invariants (`ifndef MUTATION) are left out so a mutation is only killed by a property of the spec.
#   2. If not killed, an equivalence check: the original module against the mutated one, same inputs, same start state, on every
#      output. First unbounded (PDR on the miter): a pass means the mutation can never be seen (equivalent). If PDR does not
#      finish, a BMC of depth D: a pass means no visible effect within D clocks (bounded).
#   3. If the mutant does behave differently, the proof itself (unbounded, PDR, still without helper invariants) is run on it:
#      a failure means the proof catches it deeper than D (killed); a pass means the mutant is not caught (survived).
#      A survivor is either a gap in the proof or a change that only shows for inputs the harness assumes away (for example
#      a header length above 8, which the control unit can never send). That needs a look at each one, so survivors are
#      listed in results.txt for review. No answer in time is reported as unresolved.
#      Score = killed / (killed + survived + unresolved), before review.
# Results go to build/mutate/<proof>/ and a summary table to build/mutate/summary.txt.

import argparse
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FORMAL = os.path.join(ROOT, "formal")
OUT = os.path.join(ROOT, "build", "mutate")
DEEP_TIMEOUT = 90

# proof name -> (module to mutate, kill-check depth[, kill-check engine]). The module name is the RTL module; a parameterised copy
# is found by prefix. The default kill-check engine is ABC bmc3; "smtbmc yices" suits word-level counters (MAIN), and "pdr" runs
# the kill check unbounded for harnesses whose bounded unrolling is slow (the CRC unit's bit-by-bit reference).
# Proofs whose .sby connect lines only feed helper invariants; for the others (return_path) the connected signals are the
# interface the spec is written against, so they stay.
HELPER_PEEKS = {"watchdog", "main_counter"}
PROOFS = {
	"host_fifo": ("host_fifo", 20),
	"frame_buffer": ("frame_buffer", 20),
	"uart_tx": ("uart_tx", 40),
	"branch_unit": ("branch_unit", 12),
	"crc_unit": ("crc_unit", 8, "pdr"),
	"line_codec": ("line_codec", 16),
	"watchdog": ("watchdog", 24),
	"start_router": ("start_router", 2),
	"first_counter": ("first_counter", 14),
	"header_counter": ("header_counter", 16),
	"end_counter": ("end_counter", 20),
	"main_counter": ("main_counter", 8, "smtbmc yices"),
	"entry_dispatch": ("entry_dispatch", 16),
	"return_path": ("return_path", 40),
	"uart_rx": ("uart_rx", 46),
	"control_unit": ("control_unit", 14),
}


def mutation_read(lines):
	"""The harness read with MUTATION defined, used everywhere so that cell names match between listing and applying."""
	return [l.replace("read -formal", "read -formal -D MUTATION", 1) if l.startswith("read ") else l for l in lines]


def parse_sby(path):
	"""Return the [script] lines for the prove task and the [files] list of a .sby file."""
	sections = {}
	current = None
	for line in open(path):
		line = line.rstrip("\n")
		m = re.match(r"^\[(\w+)\]", line)
		if m:
			current = m.group(1)
			sections[current] = []
			continue
		if current:
			sections[current].append(line)
	script = []
	for line in sections.get("script", []):
		m = re.match(r"^(~?)(\w+):\s*(.*)$", line)
		if m and m.group(2) in ("prove", "cover", "line", "wide"):
			neg, task, rest = m.groups()
			if (task == "prove") != (neg == "~"):
				script.append(rest)
			continue
		if line.strip():
			script.append(line)
	files = [l.strip() for l in sections.get("files", []) if l.strip()]
	return script, files


def run(cmd, cwd, timeout):
	try:
		p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
		return p.returncode, p.stdout
	except subprocess.TimeoutExpired:
		return None, ""


def module_name(workdir, script, files, base):
	"""Elaborate the harness and return the exact (possibly parameterised) name of the module under test."""
	prep = mutation_read([l for l in script if l.startswith("read") or l.startswith("prep")])
	ys = "\n".join(prep + ["tee -q -o names.txt ls"])
	open(os.path.join(workdir, "names.ys"), "w").write(ys)
	run(["yosys", "-q", "-s", "names.ys"], workdir, 120)
	text = open(os.path.join(workdir, "names.txt")).read() if os.path.exists(os.path.join(workdir, "names.txt")) else ""
	names = [l.strip() for l in text.splitlines() if l.strip().startswith("$paramod") or l.strip() == base]
	for n in names:
		if n == base or n.startswith("$paramod\\" + base + "\\") or n.startswith("$paramod$") and base in n:
			return n
	return base


def list_mutations(workdir, script, mod, n, seed):
	prep = mutation_read([l for l in script if l.startswith("read") or l.startswith("prep")])
	esc = mod.replace("\\", "\\\\").replace("$", "\\$")
	ys = "\n".join(prep + ["mutate -list %d -seed %d -none -o mutations.txt %s" % (n, seed, esc)])
	open(os.path.join(workdir, "list.ys"), "w").write(ys)
	run(["yosys", "-q", "-s", "list.ys"], workdir, 300)
	path = os.path.join(workdir, "mutations.txt")
	return [l.strip() for l in open(path) if l.strip()] if os.path.exists(path) else []


def write_sby(path, mode, depth, script_lines, files, engine="abc bmc3"):
	with open(path, "w") as f:
		if mode == "prove":
			f.write("[options]\nmode prove\n\n[engines]\n%s\n\n[script]\n" % engine)
		else:
			f.write("[options]\nmode %s\ndepth %d\n\n[engines]\n%s\n\n[script]\n" % (mode, depth, engine))
		f.write("\n".join(script_lines) + "\n\n[files]\n")
		f.write("\n".join(files) + "\n")


def kill_check(workdir, idx, script, files, mutation, depth, deep=False, proof="", engine="abc bmc3"):
	lines = []
	for l in script:
		if l.startswith("connect ") and proof in HELPER_PEEKS:
			continue  # these peeks only feed helper invariants, which are left out here
		if l.startswith("read "):
			l = l.replace("read -formal", "read -formal -D MUTATION", 1)
		lines.append(l)
		if l.startswith("prep"):
			lines.append(mutation)
	name = ("deep_%02d" if deep else "kill_%02d") % idx
	if deep or engine == "pdr":
		write_sby(os.path.join(workdir, name + ".sby"), "prove", depth, lines, files, "abc pdr")
	else:
		write_sby(os.path.join(workdir, name + ".sby"), "bmc", depth, lines, files, engine)
	rc, out = run(["sby", "-f", name + ".sby"], workdir, DEEP_TIMEOUT if deep else (900 if engine == "pdr" else 1800))
	if rc is None:
		return "timeout"
	if "DONE (PASS" in out:
		return "survived"
	if "Assert failed" in out or "DONE (FAIL" in out:
		return "killed"
	return "error"


def equivalence_check(workdir, idx, script, files, mutation, mod, depth):
	esc = mod  # Yosys scripts take the name as mutate -list prints it
	prep = mutation_read([l for l in script if l.startswith("read") or l.startswith("prep")])
	mutated = re.sub(r"-module \S+", "-module mutant", mutation)
	lines = prep + [
		"hierarchy -top %s" % esc,
		"copy %s mutant" % esc,
		mutated,
		"miter -equiv -flatten -make_assert -ignore_gold_x %s mutant miter" % esc,
		"hierarchy -top miter",
		"memory_map",
		"opt -fast",
		"setundef -undriven -anyseq",
		"setundef -zero -init",
	]
	# First an unbounded equivalence proof (PDR on the miter); if that does not finish, a bounded one of the same depth.
	name = "equiv_%02d" % idx
	write_sby(os.path.join(workdir, name + ".sby"), "prove", depth, lines, files, "abc pdr")
	rc, out = run(["sby", "-f", name + ".sby"], workdir, DEEP_TIMEOUT)
	if rc is not None and "DONE (PASS" in out:
		return "equivalent"
	if rc is not None and ("Assert failed" in out or "DONE (FAIL" in out):
		return "differs"
	name = "equivb_%02d" % idx
	write_sby(os.path.join(workdir, name + ".sby"), "bmc", depth, lines, files)
	rc, out = run(["sby", "-f", name + ".sby"], workdir, 1800)
	if rc is None:
		return "timeout"
	if "DONE (PASS" in out:
		return "bounded"
	if "Assert failed" in out or "DONE (FAIL" in out:
		return "differs"
	return "error"


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("proofs", nargs="*")
	ap.add_argument("-n", type=int, default=16)
	ap.add_argument("--seed", type=int, default=1)
	ap.add_argument("--depth", type=int, default=0)
	ap.add_argument("--retry", action="store_true", help="only reclassify the entries marked error in an earlier run")
	args = ap.parse_args()
	todo = args.proofs or list(PROOFS)
	os.makedirs(OUT, exist_ok=True)
	summary = []
	for proof in todo:
		base, depth = PROOFS[proof][:2]
		engine = PROOFS[proof][2] if len(PROOFS[proof]) > 2 else "abc bmc3"
		depth = args.depth or depth
		workdir = os.path.join(OUT, proof)
		previous = []
		if args.retry and os.path.exists(os.path.join(workdir, "results.txt")):
			previous = [l.rstrip("\n").split(None, 1) for l in open(os.path.join(workdir, "results.txt")) if l.strip()]
		else:
			shutil.rmtree(workdir, ignore_errors=True)
			os.makedirs(workdir)
		script, files = parse_sby(os.path.join(FORMAL, proof + ".sby"))
		files = [os.path.normpath(os.path.join(FORMAL, f)) for f in files]
		for f in files:
			shutil.copy(f, workdir)
		mod = module_name(workdir, script, files, base)
		muts = [m for _, m in previous] if previous else list_mutations(workdir, script, mod, args.n, args.seed)
		earlier = {m: r for r, m in previous}
		counts = {"killed": 0, "equivalent": 0, "bounded": 0, "survived": 0, "unresolved": 0, "timeout": 0, "error": 0}
		log = open(os.path.join(workdir, "results.txt"), "w")
		for i, m in enumerate(muts):
			if m.startswith("mutate -mode none") and earlier.get(m, "").startswith("baseline"):
				log.write("%-10s %s\n" % (earlier[m], m))
				continue
			if m.startswith("mutate -mode none"):
				# The unmutated design must pass the bounded check: otherwise the kill check means nothing.
				res = kill_check(workdir, i, script, files, "", depth, proof=proof, engine=engine)
				ok = res == "survived"
				log.write("%-10s %s\n" % ("baseline" if ok else "BASELINE-FAIL", m))
				if not ok:
					print("%s: the unmutated design fails the bounded check (%s)" % (proof, res))
				continue
			if earlier.get(m, "error") != "error":
				res = earlier[m]
				counts[res] = counts.get(res, 0) + 1
				log.write("%-10s %s\n" % (res, m))
				continue
			res = kill_check(workdir, i, script, files, m, depth, proof=proof, engine=engine)
			if res == "survived":
				res = equivalence_check(workdir, i, script, files, m, mod, depth)
				if res == "differs":
					# The mutant behaves differently somewhere; see whether the unbounded proof catches it deeper.
					deep = kill_check(workdir, i, script, files, m, depth, deep=True, proof=proof)
					res = "killed" if deep == "killed" else ("survived" if deep == "survived" else "unresolved")
			counts[res] += 1
			log.write("%-10s %s\n" % (res, m))
			log.flush()
		log.close()
		live = counts["killed"] + counts["survived"] + counts["unresolved"]
		score = 100.0 * counts["killed"] / live if live else 100.0
		line = "%-15s %3d mutations  killed %3d  equivalent %3d  no effect in %d clocks %3d  survived %3d  unresolved %2d  timeout %2d  error %2d  score %5.1f %%" % (
			proof, sum(counts.values()), counts["killed"], counts["equivalent"], depth, counts["bounded"], counts["survived"],
			counts["unresolved"] + 0, counts["timeout"], counts["error"], score)
		print(line, flush=True)
		summary.append(line)
	with open(os.path.join(OUT, "summary.txt"), "a") as f:
		f.write("\n".join(summary) + "\n")
	return 0


if __name__ == "__main__":
	sys.exit(main())
