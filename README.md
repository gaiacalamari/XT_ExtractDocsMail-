# XT_ExtractDocsMail

An X-Tension for **X-Ways Forensics (x64)** that automatically exports the files of a forensic image **organized by category**, rebuilding each file's original path. It is designed to run entirely from the command line: one command, no GUI interaction.

## What it does

For every file in the volume snapshot it reads the category assigned by X-Ways (`XWF_GetItemType`) and copies the file's content into a folder structure:

```
<Root>\<Evidence>\<Category>\<original file path>
```

Category names are not hard-coded: the tool uses whatever category X-Ways returns, so **every** category present is exported (Documents, Spreadsheets, Presentations, Pictures, Video, E-mail, Archives, "Other/unknown type", …), not just a fixed subset.

## Usage

```bat
set "XT_OUT=Y:\Export" && "C:\xwf21.7\xwforensics64.exe" "NewCase:W:\xways" "AddImage:Y:\Images\*.E01" RVS:~ "XT:C:\xwf21.7\XTension\XT_ExtractDocsMail.dll" auto
```

## Important prerequisite

The tool only exports files that X-Ways has **already assigned a category** to. Categories are populated by **file type verification**, which is one of the *Refine Volume Snapshot* (RVS) operations.

- In the command above `RVS:~` runs before `XT:`, so the snapshot is refined before the export. Make sure your RVS settings (or the `.dlg` you use) include file type verification.
- If you run the X-Tension in *standalone* mode (`XT:` without an RVS that verifies types) on an unrefined snapshot, items have no category and **nothing is exported**. This is the most common cause of "it looks fine but produces no output".

## Features

- **Original path preserved**, reconstructed by walking up each item's parents.
- **Long paths** (`\\?\`) handled: no failures at the 260-character limit; Windows reserved names are handled too.
- **Collision-safe**: files sharing the same path (e.g. recovered/deleted items) are saved with `_<ID>` before the extension instead of overwriting.
- Volume snapshot opened **read-only**.
- **Summary log** in the Messages window (files exported / errors, per evidence object and overall).

## Two modes (both automatic)

1. **RVS** — with `RVS:~ "XT:...XT_ExtractDocsMail.dll"`: X-Ways calls the X-Tension for each item during Refine Volume Snapshot. This is the recommended path, because it guarantees that types (and therefore categories) have already been assigned.
2. **Standalone / RUN** — with `"XT:...XT_ExtractDocsMail.dll"` from the menu or command line without RVS: the X-Tension enumerates all evidence objects of the case itself and exports. Requires that file types have already been verified.

## Installation

Two options:

**A. Prebuilt DLL (recommended for most users)**
Download `XT_ExtractDocsMail.dll` from the [Releases](../../releases) page and place it wherever you keep your X-Tensions (e.g. `C:\xwf21.7\XTension\`). Reference it with the `XT:` parameter as shown in *Usage*.

**B. Build from source**
See [Build](#build) below. `XT_API.pas` is already included in this repository, so no external dependency is needed.

## Environment variables

| Variable  | Required | Description |
|-----------|----------|-------------|
| `XT_OUT`  | no       | Output root folder. If unset, falls back to `XT_DOCS_OUT`, then to the default `D:\Export`. |
| `XT_CATS` | no       | Optional filter: comma-separated list of category substrings, lowercase and without spaces. If unset, all categories are exported. |

Filter example:

```bat
set "XT_CATS=document,spreadsheet,presentation,picture,video,mail"
```

## Requirements

- X-Ways Forensics **x64** (tested with the 21.x series; category retrieval requires v18.9 or later).
- Windows.
- To build: **Lazarus 2.x / FreePascal 3.2.x**.

## Build

1. Open `XT_ExtractDocsMail.lpr` in Lazarus (`XT_API.pas` is already in the repository, next to it).
2. Project → Compiler Options → Target OS/CPU: **Win64 / x86_64**.
3. Build. The output is `XT_ExtractDocsMail.dll`.

> The X-Tension must be built as **64-bit**.

## Repository layout

```
XT_ExtractDocsMail/
├─ XT_ExtractDocsMail.lpr    # X-Tension source
├─ XT_API.pas                # X-Tension API binding (from hmrc/XT_XWF-AutoCTR, unmodified)
├─ README.md
├─ LICENSE
├─ gitignore
├─ build
    ├─ test E01
    └─ XT_ExtractDocsMail.dll
└─ NOTICE
```

The compiled `XT_ExtractDocsMail.dll` is distributed via the [Releases](../../releases) page rather than committed to the source tree.

## Attribution & licence

- Built on the X-Tension API of [hmrc/XT_XWF-AutoCTR](https://github.com/hmrc/XT_XWF-AutoCTR) (Ted Smith / HMRC), which supplies `XT_API.pas`.
- Released under the **Apache License 2.0**, consistent with the upstream project. See `LICENSE` and `NOTICE`.

X-Ways Forensics is a trademark of X-Ways Software Technology AG. This project is an independent third-party X-Tension and is not affiliated with or endorsed by X-Ways Software Technology AG.
