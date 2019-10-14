#!/usr/bin/env python3

# 1Password Import Batch Processor 1.0
# Batch tool converting large, complex 1Password libraries for use with pass
# Author: Narcis M PAP, London, Oct 2019

from argparse import ArgumentParser
import subprocess, os, time
import asyncio, multiprocessing

PWDCOMMAND = "./1pwdtopass.rb"
ALLOWED = ["Cards", "Notes", "SSN", "Wireless", "Software", "Logins", "All"]
sem = asyncio.Semaphore(multiprocessing.cpu_count())

async def process_import(pos, group, f_type, pif_file):
	print("[%s] Discovered %s (%s) into %s" % ('%03d' % pos, pif_file, f_type, group))
	command = '%s -d %s "%s"' % (PWDCOMMAND, group, pif_file)

	if args.sim:
		command += " --simulate"
	if args.dns:
		command += " --dns"

	async with sem:
		process = await asyncio.create_subprocess_shell(
			command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
		)

		stdout, stderr = await process.communicate()
		if process.returncode == 0:
			print("[%s] Done:" % ('%03d' % pos), "(pid = " + str(process.pid) + ")", flush=True)
		else:
			print(
				"[%s] Failed:" % ('%03d' % pos), "(pid = " + str(process.pid) + ")", flush=True
			)

		return stdout.decode().strip()

if __name__ == '__main__':
	parser = ArgumentParser()
	parser.add_argument("-d", "--dir", dest="dir", help="input directory", metavar="DIR", required=True)
	parser.add_argument("-s", "--simulate", dest="sim", help="Run a simulated entry", action="store_true")
	parser.add_argument("-j", "--dns", dest="dns", help="Reserse DNS naming for logins: com.google.mail", action="store_true")
	args = parser.parse_args()

	jobs, pos = [], 0	
	for group in os.listdir(args.dir):
		sd = os.path.join(args.dir,group)
		if os.path.isdir(sd):
			print("[+] Group: %s" % group)

			for idir in os.listdir(sd):
				ad = os.path.join(sd,idir)
				if os.path.isdir(ad):
					pif_type = idir.split(" ")[0]
					pif_file = os.path.join(ad, "data.1pif")

					if pif_type not in ALLOWED:
						raise Exception("Unknown dir format: %s at %s", pif_type, sd)

					if not os.path.isfile(pif_file):
						raise Exception("Cannot find %s", pif_file)
					
					jobs.append([pos, group, pif_type, pif_file])
					pos += 1
	
	print("[+] Running %d jobs"% len(jobs))

	loop = asyncio.get_event_loop()
	sch_jobs = asyncio.gather(*[asyncio.ensure_future(process_import(*d)) for d in jobs])
	loop.run_until_complete(sch_jobs)
	loop.close()

	print("[DONE]")
