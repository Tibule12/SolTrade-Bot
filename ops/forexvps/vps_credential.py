#!/usr/bin/env python3
"""Store/materialize the SolTrade VPS password through the desktop secret service.

The password is never printed. `store` reads it from stdin or --from-file;
`materialize` writes a mode-0600 temporary file for FreeRDP.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import gi
gi.require_version("Secret", "1")
from gi.repository import Secret

SCHEMA=Secret.Schema.new("com.soltrade.vps",Secret.SchemaFlags.NONE,
    {"server":Secret.SchemaAttributeType.STRING,"username":Secret.SchemaAttributeType.STRING})
ATTRIBUTES={"server":"38.89.79.28:42014","username":"trader"}
LABEL="SolTrade ForexVPS Windows credential"


def lookup()->str|None:
    return Secret.password_lookup_sync(SCHEMA,ATTRIBUTES,None)


def main()->int:
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest="action",required=True)
    store=sub.add_parser("store");store.add_argument("--from-file",type=Path)
    materialize=sub.add_parser("materialize");materialize.add_argument("path",type=Path)
    sub.add_parser("status")
    args=parser.parse_args()
    if args.action=="store":
        password=args.from_file.read_text() if args.from_file else input()
        if not password:raise SystemExit("empty password refused")
        if not Secret.password_store_sync(SCHEMA,ATTRIBUTES,Secret.COLLECTION_DEFAULT,LABEL,password,None):raise SystemExit("secret service rejected credential")
        print("stored in desktop keyring")
    elif args.action=="materialize":
        password=lookup()
        if password is None:raise SystemExit("credential absent")
        fd=os.open(args.path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
        with os.fdopen(fd,"w") as stream:stream.write(password)
        print(f"materialized mode 0600 at {args.path}")
    else:print("present" if lookup() is not None else "absent")
    return 0


if __name__=="__main__":raise SystemExit(main())
