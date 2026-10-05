#!/usr/bin/env python3
"""Reproduce buffer attribution from a GDS_logs.zip; no external packages.
Usage: python3 analyze.py /path/to/GDS_logs.zip > analysis.json
"""
import collections, hashlib, json, re, sys, zipfile
from pathlib import Path
archive=Path(sys.argv[1])
with zipfile.ZipFile(archive) as z:
    root='runs/wokwi/'
    netlist=z.read(root+'final/nl/tt_um_calincalin644_fpu_fp32.nl.v').decode()
    instances={};drivers={}
    for m in re.finditer(r'(sky130_fd_sc_hd__\w+)\s+(\S+)\s*\((.*?)\);',netlist,re.S):
        ports={p:n.strip() for p,n in re.findall(r'\.(\w+)\((.*?)\)',m[3])}
        instances[m[2]]={'cell':m[1],'ports':ports}
        for pin in ['X','Y','Q']:
            if pin in ports:drivers[ports[pin]]=m[2]
    # Report and named nets refer to this exact mapped artifact. No inference
    # through assign aliases is needed for the violating nets in this run.
    reports=[n for n in z.namelist() if n.endswith('/max_ss_100C_1v60/checks.rpt') and 'stapostpnr' in n]
    assert len(reports)==1,reports
    report=z.read(reports[0]).decode()
    slew=report.split('\nmax slew\n')[1].split('\nmax fanout\n')[0]
    fanout=report.split('\nmax fanout\n')[1].split('\nmax capacitance\n')[0]
    cap=report.split('\nmax capacitance\n')[1].split('\n\n\n')[0]
    totals=collections.Counter();nets=collections.defaultdict(set);rows=[]
    for line in slew.splitlines():
        m=re.match(r'(\S+)\s+([\d.]+)\s+([\d.]+)\s+(-[\d.]+) \(VIOLATED\)',line)
        if not m:continue
        name,pin=m[1].rsplit('/',1);net=instances[name]['ports'][pin]
        driver=drivers[net];cell=instances[driver]['cell']
        totals[cell]+=1;nets[cell].add(net)
        rows.append({'pin':m[1],'driver':driver,'cell':cell,'net':net,'limit_ns':float(m[2]),'slew_ns':float(m[3])})
    assert sum(totals.values())==slew.count('(VIOLATED)')
    caps=[]
    for line in cap.splitlines():
        m=re.match(r'(\S+)\s+([\d.]+)\s+([\d.]+)\s+(-[\d.]+) \(VIOLATED\)',line)
        if m:
            name,pin=m[1].rsplit('/',1)
            caps.append({'pin':m[1],'cell':instances[name]['cell'],'limit_pf':float(m[2]),'cap_pf':float(m[3])})
    categories={}
    for prefix in ['fanout','input','load_slew','hold']:
        categories[prefix]=dict(collections.Counter(v['cell'] for n,v in instances.items() if n.startswith(prefix)))
    delay=[n for n,v in instances.items() if '__clkdlybuf' in v['cell']]
    run=json.loads(z.read(root+'final/commit_id.json'))
    config=json.loads(z.read(root+'06-yosys-synthesis/config.json'))
    result={'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'run':run,'scope':'max_ss_100C_1v60 post-route checks; counts are pins, not unique nets','slew_violation_count':sum(totals.values()),'slew_pins_by_driver_cell':dict(totals),'unique_slew_nets_by_driver_cell':{k:len(v) for k,v in nets.items()},'worst_slew_pin':rows[0],'cap_violations':caps,'fanout_violation_count':fanout.count('(VIOLATED)'),'repair_instance_prefix_counts':categories,'clock_delay_buffer_count':len(delay)}
    # Preserve exact excerpts establishing which stage inserted the cells.
    gpl=next(n for n in z.namelist() if n.endswith('/openroad-repairdesignpostgpl.log'))
    cts=next(n for n in z.namelist() if n.endswith('/openroad-resizertimingpostcts.log'))
    result['repair_log_evidence']=[line for f in [gpl,cts] for line in z.read(f).decode().splitlines() if ('Inserted' in line and ('buffer' in line or 'input' in line)) or line.startswith('+ repair_')]
    print(json.dumps(result,indent=2))
