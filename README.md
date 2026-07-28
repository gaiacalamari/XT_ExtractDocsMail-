# XT_ExtractDocsMail
An X-Tension for X-Ways Forensics (x64) that exports the files of a forensic image organized by category, rebuilding each file's original path. Designed to run fully automatically from the command line: one command, no GUI interaction.

<code>set "XT_OUT=Y:\Export" && "C:\xwf21.7\xwforensics64.exe" "NewCase:W:\xways" "AddImage:Y:\Images\*.E01" RVS:~ "XT:C:\xwf21.7\XT_XWF-AutoCTR-main\XT_ExtractDocsMail.dll" auto</code>

For every file in the volume snapshot it reads the category assigned by X-Ways (XWF_GetItemType) and copies the file's content into a folder structure:
<code><Root>\<Evidence>\<Category>\<original file path></code>

Category names are not hard-coded: the tool uses whatever category X-Ways returns, so every category present is exported (Documents, Spreadsheets, Presentations, Pictures, Video, E-mail, Archives, "Other/unknown type", etc.), not just a fixed subset. Example output:

<code>Y:\Export\Disk1\\"Full Path"\report.docx
      Y:\Export\Disk1\\"Full Path"\budget.xlsx
      Y:\Export\Disk1\\"Full Path"\slides.pptx
      Y:\Export\Disk2\\"Full Path"\report.docx
      Y:\Export\Disk2\\"Full Path"\photo001.jpg
      Y:\Export\Disk2\\"Full Path"\message.eml</code>

Features:
- Original path preserved, reconstructed by walking up each item's parents.
- Long paths (\\?\) handled: no failures at the 260-character limit.
- Collision-safe: files sharing the same path (e.g. recovered/deleted items) are saved with _<ID> before the extension instead of overwriting.
- Volume snapshot opened read-only.
- Summary log in the Messages window (files exported / errors, per evidence object and overall).

# Requirements
X-Ways Forensics x64 (tested with the 21.x series).
Windows.
To build: Lazarus 2.x / FreePascal 3.2.x.
The XT_API.pas file from hmrc/XT_XWF-AutoCTR, not included here: copy it next to XT_ExtractDocsMail.lpr before compiling.

# Build
1. Put XT_ExtractDocsMail.lpr and XT_API.pas in the same folder.
2. Open the .lpr in Lazarus.
3. Project → Compiler Options → Target OS/CPU: Win64 / x86_64.
4. Build. The output is XT_ExtractDocsMail.dll.

Environment variables
Variable	Required	Description
XT_OUT	no	Output root folder. If unset, falls back to XT_DOCS_OUT, then to the default D:\Export.
XT_CATS	no	Optional filter: comma-separated list of category substrings, lowercase and without spaces. If unset, all categories are exported.

Filter example
<code>set "XT_CATS=document,spreadsheet,presentation,picture,video,mail"</code>

Attribution & licence
- Built on the X-Tension API of hmrc/XT_XWF-AutoCTR (Ted Smith / HMRC), which supplies XT_API.pas.
- Released under the Apache License 2.0, consistent with the upstream project.
