library XT_ExtractDocsMail;
{
  ============================================================================
  XT_ExtractDocsMail  -  X-Tension per X-Ways Forensics (x64)
  ----------------------------------------------------------------------------
  Esporta i file dell'immagine ORGANIZZATI PER CATEGORIA X-Ways, ricostruendo
  il percorso originale. Layout di output:

      <Root>\<Evidence>\<Categoria>\<percorso originale del file>

  La <Categoria> e' quella che X-Ways stessa assegna al file (Documents,
  Spreadsheets, Presentations, Pictures, Video, E-mail, Archives, ... e
  "Other/unknown type"): NON e' hardcoded, quindi escono TUTTE le categorie,
  non solo documenti e posta.

  DUE MODALITA' (automatiche):
  1) Da RIGA DI COMANDO con "XT:...XT_ExtractDocsMail.dll" (nOpType=RUN):
     l'X-Tension enumera da sola tutti gli evidence object ed esporta.
  2) Dentro il Refine Volume Snapshot (nOpType=RVS): X-Ways chiama
     XT_ProcessItemEx per ogni item.

  VARIABILI D'AMBIENTE (nessuna ricompilazione necessaria):
    XT_OUT   = cartella radice di output. Se assente usa XT_DOCS_OUT, poi il
               default qui sotto.
    XT_CATS  = (opzionale) elenco di sotto-stringhe di categoria separate da
               virgola, in minuscolo e SENZA spazi, per esportare solo alcune
               categorie. Esempio:
                   set "XT_CATS=document,spreadsheet,presentation,picture,video,mail"
               Se assente, esporta TUTTE le categorie.

  Basata sull'API di hmrc/XT_XWF-AutoCTR (Apache-2.0). Richiede XT_API.pas
  accanto a questo sorgente. Compilare come DLL x86_64-win64.
  ============================================================================
}
{$mode Delphi}{$H+}

uses
  Classes, SysUtils, Windows, XT_API;

const
  DEFAULT_OUT : UnicodeString = 'D:\Export';   // usato se XT_OUT/XT_DOCS_OUT assenti

  CHUNK = 1024 * 1024;   // buffer di lettura/scrittura (1 MB)

  OPEN_EVOBJ_VS_READONLY = $02;        // apre lo snapshot in sola lettura
  OPEN_ITEM_SUPPRESSERR  = $02;        // contenuto logico + niente popup
  ITEMTYPE_CATEGORY      = $40000000;  // XWF_GetItemType restituisce la CATEGORIA

var
  MainWnd       : THandle;
  CurrentVolume : THandle;
  BaseOut       : UnicodeString;
  FilterCats    : UnicodeString;   // '' = tutte le categorie
  EvdName       : UnicodeString;
  cntFiles, cntErr : Int64;
  HasRun        : Boolean;

// ---------------------------------------------------------------------------
// Utilità
// ---------------------------------------------------------------------------
procedure Log(const S: UnicodeString);
begin
  XWF_OutputMessage(PWideChar(S), 0);
end;

function AsciiLower(const S: UnicodeString): UnicodeString;
var i: Integer; c: WideChar;
begin
  Result := S;
  for i := 1 to Length(Result) do
  begin
    c := Result[i];
    if (c >= 'A') and (c <= 'Z') then Result[i] := WideChar(Ord(c) + 32);
  end;
end;

// Rende un singolo componente di percorso valido per il filesystem di Windows
function SanitizeComponent(const S: UnicodeString): UnicodeString;
var i: Integer; c: WideChar;
begin
  Result := S;
  for i := 1 to Length(Result) do
  begin
    c := Result[i];
    if (c < #32) or (c = '<') or (c = '>') or (c = ':') or (c = '"') or
       (c = '/') or (c = '\') or (c = '|') or (c = '?') or (c = '*') then
      Result[i] := '_';
  end;
  while (Length(Result) > 0) and
        ((Result[Length(Result)] = '.') or (Result[Length(Result)] = ' ')) do
    SetLength(Result, Length(Result) - 1);
  if Result = '' then Result := '_';
end;

function LongPath(const P: UnicodeString): UnicodeString;
begin
  if Copy(P, 1, 4) = '\\?\' then Result := P
  else if Copy(P, 1, 2) = '\\' then Result := '\\?\UNC\' + Copy(P, 3, MaxInt)
  else Result := '\\?\' + P;
end;

function PathExists(const P: UnicodeString): Boolean;
begin
  Result := GetFileAttributesW(PWideChar(LongPath(P))) <> INVALID_FILE_ATTRIBUTES;
end;

function LastPos(const S: UnicodeString; C: WideChar): Integer;
var i: Integer;
begin
  Result := 0;
  for i := Length(S) downto 1 do
    if S[i] = C then begin Result := i; Break; end;
end;

function DirOf(const P: UnicodeString): UnicodeString;
var k: Integer;
begin
  k := LastPos(P, '\');
  if k > 0 then Result := Copy(P, 1, k - 1) else Result := '';
end;

function ExtOf(const P: UnicodeString): UnicodeString;
var kdot, kslash: Integer;
begin
  kdot := LastPos(P, '.'); kslash := LastPos(P, '\');
  if (kdot > kslash) and (kdot > 0) then Result := Copy(P, kdot, MaxInt)
  else Result := '';
end;

procedure MakeDirs(const Dir: UnicodeString);
var i: Integer; cur: UnicodeString;
begin
  cur := '';
  for i := 1 to Length(Dir) do
  begin
    if Dir[i] = '\' then
    begin
      if (cur <> '') and (cur[Length(cur)] <> ':') then
        CreateDirectoryW(PWideChar(LongPath(cur)), nil);
      cur := cur + '\';
    end
    else
      cur := cur + Dir[i];
  end;
  if (cur <> '') and (cur[Length(cur)] <> ':') then
    CreateDirectoryW(PWideChar(LongPath(cur)), nil);
end;

function EnvOr(const VarName, Def: UnicodeString): UnicodeString;
var buf: array[0..1023] of WideChar; n: DWord;
begin
  n := GetEnvironmentVariableW(PWideChar(VarName), @buf[0], Length(buf));
  if (n > 0) and (n < DWord(Length(buf))) then
    Result := UnicodeString(PWideChar(@buf[0]))
  else
    Result := Def;
end;

// True se la categoria (minuscola) e' fra quelle richieste in XT_CATS.
// Se XT_CATS e' vuoto -> tutte ammesse.
function CatAllowed(const lcat: UnicodeString): Boolean;
var i, start, len: Integer; tok: UnicodeString;
begin
  if FilterCats = '' then begin Result := True; Exit; end;
  Result := False;
  len := Length(FilterCats);
  start := 1;
  i := 1;
  while i <= len + 1 do
  begin
    if (i > len) or (FilterCats[i] = ',') then
    begin
      tok := Copy(FilterCats, start, i - start);
      if (tok <> '') and (Pos(tok, lcat) > 0) then begin Result := True; Exit; end;
      start := i + 1;
    end;
    Inc(i);
  end;
end;

// Ricostruisce dir\...\nomefile risalendo i genitori
function BuildRelPath(nItemID: LongInt): UnicodeString;
var pName: PWideChar; nm: UnicodeString; parent, guard: LongInt;
begin
  Result := '';
  guard := 0;
  while (nItemID >= 0) and (guard < 8192) do
  begin
    pName := XWF_GetItemName(nItemID);
    if pName = nil then Break;
    nm := SanitizeComponent(UnicodeString(pName));
    if Result = '' then Result := nm
    else Result := nm + '\' + Result;
    parent := XWF_GetItemParent(nItemID);
    if parent = nItemID then Break;
    nItemID := parent;
    Inc(guard);
  end;
end;

// Copia il contenuto dell'item sotto DestBase\<percorso originale>
function ExportItem(nItemID: LongInt; const DestBase: UnicodeString): Boolean;
var
  rel, fullPath, candidate, ext, base: UnicodeString;
  hItem, hFile: THandle;
  sz, ofs: Int64;
  toRead, got, written: DWord;
  buf: PAnsiChar;
begin
  Result := False;
  sz := XWF_GetItemSize(nItemID);
  if sz < 0 then Exit;

  rel := BuildRelPath(nItemID);
  fullPath := DestBase + '\' + rel;
  MakeDirs(DirOf(fullPath));

  candidate := fullPath;
  if PathExists(candidate) then
  begin
    ext  := ExtOf(fullPath);
    base := Copy(fullPath, 1, Length(fullPath) - Length(ext));
    candidate := base + '_' + IntToStr(nItemID) + ext;
  end;

  hItem := XWF_OpenItem(CurrentVolume, nItemID, OPEN_ITEM_SUPPRESSERR);
  if hItem = 0 then Exit;
  try
    hFile := CreateFileW(PWideChar(LongPath(candidate)), GENERIC_WRITE, 0, nil,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if hFile = INVALID_HANDLE_VALUE then Exit;
    try
      GetMem(buf, CHUNK);
      try
        ofs := 0;
        while ofs < sz do
        begin
          if (sz - ofs) < CHUNK then toRead := DWord(sz - ofs) else toRead := CHUNK;
          got := XWF_Read(hItem, ofs, buf, toRead);
          if got = 0 then Break;
          if not WriteFile(hFile, buf^, got, written, nil) then Break;
          Inc(ofs, got);
        end;
      finally
        FreeMem(buf);
      end;
    finally
      CloseHandle(hFile);
    end;
    Result := True;
  finally
    XWF_Close(hItem);
  end;
end;

// Legge la categoria dell'item e, se ammessa, lo esporta nella cartella
// <BaseOut>\<Evidence>\<Categoria>\<percorso>
procedure ExportByCategory(nItemID: LongInt);
var
  descr : array[0..255] of WideChar;
  cat, lcat, destBase : UnicodeString;
begin
  if XWF_GetItemSize(nItemID) < 0 then Exit;   // directory / solo metadati: salta

  FillChar(descr, SizeOf(descr), 0);
  XWF_GetItemType(nItemID, @descr[0], DWord(Length(descr)) or ITEMTYPE_CATEGORY);
  if descr[0] = #0 then Exit;                  // nessuna categoria assegnata

  cat  := UnicodeString(PWideChar(@descr[0]));
  lcat := AsciiLower(cat);
  if not CatAllowed(lcat) then Exit;

  destBase := BaseOut + '\' + EvdName + '\' + SanitizeComponent(cat);
  if ExportItem(nItemID, destBase) then Inc(cntFiles) else Inc(cntErr);
end;

// Apre un evidence object, seleziona lo snapshot ed esporta tutti gli item.
procedure ProcessOneEvidence(hEv: THandle);
var
  hVol : THandle;
  buf  : array[0..255] of WideChar;
  total, i : LongInt;
  f0, e0 : Int64;
begin
  hVol := XWF_OpenEvObj(hEv, OPEN_EVOBJ_VS_READONLY);
  if hVol = 0 then begin Log('[ERR] Apertura evidence object fallita.'); Exit; end;
  try
    XWF_SelectVolumeSnapshot(hVol);
    CurrentVolume := hVol;

    FillChar(buf, SizeOf(buf), 0);
    XWF_GetEvObjProp(hEv, 8, @buf[0]);   // 8 = titolo abbreviato
    EvdName := SanitizeComponent(UnicodeString(PWideChar(@buf[0])));
    if EvdName = '' then EvdName := 'Evidence';

    f0 := cntFiles; e0 := cntErr;
    total := LongInt(XWF_GetItemCount(nil));
    Log('== Evidence: ' + EvdName + '  (item: ' + IntToStr(total) + ') ==');

    for i := 0 to total - 1 do
      ExportByCategory(i);

    Log('   -> Esportati: ' + IntToStr(cntFiles - f0)
        + '  Errori: ' + IntToStr(cntErr - e0));
  finally
    XWF_CloseEvObj(hEv);
  end;
end;

procedure RunStandalone;
var hEv, hNext: THandle;
begin
  cntFiles := 0; cntErr := 0;
  Log('== XT_ExtractDocsMail (command line) ==  Output -> ' + BaseOut);
  if FilterCats <> '' then Log('   Filtro categorie: ' + FilterCats)
  else Log('   Categorie: TUTTE');

  hEv := XWF_GetFirstEvObj(nil);
  if hEv = 0 then begin Log('[ATTENZIONE] Nessun evidence object nel caso.'); Exit; end;

  while hEv <> 0 do
  begin
    hNext := XWF_GetNextEvObj(hEv, nil);
    ProcessOneEvidence(hEv);
    hEv := hNext;
  end;

  Log('== TOTALE ==  File esportati: ' + IntToStr(cntFiles)
      + '  Errori: ' + IntToStr(cntErr));
end;

// ---------------------------------------------------------------------------
// API X-Tension
// ---------------------------------------------------------------------------
function XT_Init(nVersion, nFlags: DWord; hMainWnd: THandle; lpReserved: Pointer): LongInt; stdcall; export;
begin
  MainWnd := hMainWnd;
  HasRun  := False;
  Result  := 1;
end;

function XT_About(hMainWnd: THandle; lpReserved: Pointer): LongWord; stdcall; export;
begin
  MessageBoxW(hMainWnd,
    'XT_ExtractDocsMail: esporta i file organizzati per categoria X-Ways '
    + '(Documents, Spreadsheets, Presentations, Pictures, Video, E-mail, ...) '
    + 'ricostruendo il percorso originale. Da riga di comando o via RVS. '
    + 'Output: XT_OUT. Filtro opzionale: XT_CATS.',
    'XT_ExtractDocsMail', MB_ICONINFORMATION);
  Result := 0;
end;

function XT_Prepare(hVolume, hEvidence: THandle; nOpType: DWord; lpReserved: Pointer): Integer; stdcall; export;
var buf: array[0..255] of WideChar;
begin
  BaseOut    := EnvOr('XT_OUT', EnvOr('XT_DOCS_OUT', DEFAULT_OUT));
  FilterCats := AsciiLower(EnvOr('XT_CATS', ''));

  if nOpType = XT_ACTION_RVS then
  begin
    CurrentVolume := hVolume;
    FillChar(buf, SizeOf(buf), 0);
    XWF_GetEvObjProp(hEvidence, 8, @buf[0]);
    EvdName := SanitizeComponent(UnicodeString(PWideChar(@buf[0])));
    if EvdName = '' then EvdName := 'Evidence';
    cntFiles := 0; cntErr := 0;
    Log('== XT_ExtractDocsMail (RVS) == Evidence: ' + EvdName + '  Output -> ' + BaseOut);
    Result := XT_PREPARE_CALLPI;
    Exit;
  end;

  if not HasRun then
  begin
    HasRun := True;
    RunStandalone;
  end;
  Result := 0;
end;

function XT_ProcessItemEx(nItemID: LongWord; lpReserved: Pointer): Integer; stdcall; export;
begin
  Result := 0;
  ExportByCategory(LongInt(nItemID));
end;

function XT_Finalize(hVolume, hEvidence: THandle; nOpType: DWord; lpReserved: Pointer): Integer; stdcall; export;
begin
  if nOpType = XT_ACTION_RVS then
    Log('== ' + EvdName + ' completato ==  File esportati: ' + IntToStr(cntFiles)
        + '  Errori: ' + IntToStr(cntErr));
  Result := 0;
end;

function XT_Done(lpReserved: Pointer): Integer; stdcall; export;
begin
  Result := 0;
end;

exports
  XT_Init,
  XT_About,
  XT_Prepare,
  XT_ProcessItemEx,
  XT_Finalize,
  XT_Done;

begin
end.
