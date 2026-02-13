---
name: godot-dotnet-build
description: Build and verify Godot C# projects with dotnet build. Use when asked to build/compile/verify a Godot project, check C# compilation after changes, or validate before committing.
---

# Godot Dotnet Build

## Overview

Run a C# build for Godot projects using `dotnet build` against the project `.csproj` to verify compilation.

## Workflow

1. Locate the project `.csproj` (prefer explicit path).
   - If unsure, search: `rg --files -g "*.csproj"`.
2. If C# files were added/renamed/moved, regenerate Godot solutions first:
   - `godot4 --build-solutions --path .`
   - On Windows/WSL, use `godot4.exe`.
3. Build the project:
   - `dotnet build "<Project>.csproj"`
   - On Windows/WSL, use `dotnet.exe`.
4. Report results and surface any build errors clearly.

## Rules

- Always run the build from the project root unless the `.csproj` dictates otherwise.
- If multiple `.csproj` files exist, ask which one to build.
- Do not skip the build step when the user requests verification.
