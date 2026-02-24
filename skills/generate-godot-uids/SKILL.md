---
name: generate-godot-uids
description: INVOKE/LOAD WHEN CREATING OR MODIFYING .tscn FILES IN GODOT. Generate valid Godot ResourceUID strings via CLI and apply them when creating or editing Godot resources (scenes .tscn, resources .tres/.res, .import files, .uid sidecars, project.godot run/main_scene, and ext_resource/metadata uid fields). Use whenever a uid="uid://..." value or .uid file is required, or when replacing placeholder/handmade IDs.
---

# Generate Godot UIDs

## Overview

Use the bundled CLI generator to create valid `uid://...` strings. Never invent or handcraft UIDs.

## UID Workflow

1. Find every UID slot you are touching (scene header, ext_resource entries, metadata, .uid files, .import entries, project.godot run/main_scene).
2. Generate fresh UIDs with the script:
   - `python3 scripts/gen_godot_uid.py`
   - `python3 scripts/gen_godot_uid.py --count 5`
3. Paste the generated `uid://...` string exactly.
   - For `.uid` sidecar files, the file content should be just the UID on one line.
4. If you copy or duplicate a resource, generate a new UID for the copy unless there is a deliberate reason to reuse (rare).

## Rules

- Do not create human-readable, mnemonic, or hyphenated IDs.
- Do not reuse UIDs across different resource paths.
- If a placeholder UID exists (ex: `4-spaceship`), replace it with a generated UID.

## Script

- `scripts/gen_godot_uid.py` outputs Godot-style `uid://` strings using a CSPRNG-backed 64-bit value encoded in base36.
- Options:
  - `--count N` to emit multiple UIDs
  - `--bare` to emit without the `uid://` prefix

## Example

```
[gd_scene load_steps=3 format=3 uid="uid://<generated>"]
[ext_resource type="Script" uid="uid://<generated>" path="res://Scripts/Foo.cs" id="1_foo"]
```
