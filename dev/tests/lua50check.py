"""Static scan for Lua 5.1+ / retail-only constructs that break on the 1.12 client (Lua 5.0)."""
import re, sys, pathlib

def strip(src):
    """Blank out comments and string contents, keep line structure."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith('--[[', i) or src.startswith('--[=[', i):
            end = src.find(']]', i)
            end = n if end < 0 else end + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:end])); i = end
        elif src.startswith('--', i):
            end = src.find('\n', i)
            end = n if end < 0 else end
            out.append(' ' * (end - i)); i = end
        elif src[i] in '"\'':
            q, j = src[i], i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == '\\' else 1
            out.append(q + ' ' * (j - i - 1) + q); i = j + 1
        elif src.startswith('[[', i):
            end = src.find(']]', i) + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:end])); i = end
        else:
            out.append(src[i]); i += 1
    return ''.join(out)

RULES = [
    (r'#', 'length operator # (use table.getn)'),
    (r'%', 'modulo operator % (use ns.Mod)'),
    (r'\.\.\.', 'vararg ...'),
    (r'//', 'integer division'),
    (r'\bgoto\b', 'goto'),
    (r'\bstring\.(match|gmatch)\b', 'string.match/gmatch (5.1)'),
    (r'\bselect\s*\(', 'select()'),
    (r'\btable\.unpack\b|\bmath\.fmod\b|\bmath\.huge\b', '5.1+ library function'),
    (r'["\']\s*\)\s*:\s*\w+\s*\(', 'method call on a string literal'),
    (r'\b\w+\s*:\s*(sub|gsub|format|find|lower|upper|len|rep|byte|match|gmatch)\s*\(', 'string method call'),
    (r'\bC_Timer\b|\bSOUNDKIT\b|\bBreakUpLargeNumbers\b|\bGetMinimapShape\b|\bstrtrim\b|\bprint\s*\(', 'retail-only global'),
    (r':(SetSize|SetColorTexture|SetEnabled|SetShown|SetFormattedText)\s*\(', 'retail-only widget method'),
]
# These live inside strings, so they are matched against the raw line.
RAW_RULES = [
    (r'BackdropTemplate|BasicFrameTemplate', 'retail-only template'),
    (r'GameFontNormalHuge', 'font template missing in 1.12'),
    (r'"AnyUp"', 'AnyUp click type (2.0+)'),
    (r'INV_Misc_Food_10[45]|INV_Gizmo_FelIronBomb|Spell_Shadow_MindBomb', 'icon missing in 1.12'),
]

def check(path):
    src = pathlib.Path(path).read_text()
    code = strip(src)
    problems = []
    for ln, line in enumerate(code.split('\n'), 1):
        raw = src.split(chr(10))[ln-1]
        if not raw.strip().startswith('--'):
            for pat, why in RAW_RULES:
                if re.search(pat, raw):
                    problems.append(f'{path}:{ln}: {why}: {raw.strip()}')
        for pat, why in RULES:
            if re.search(pat, line):
                problems.append(f'{path}:{ln}: {why}: {src.split(chr(10))[ln-1].strip()}')
        # SetScript handlers must not take parameters
        m = re.search(r'SetScript\(\s*"\w+"\s*,\s*function\s*\(\s*\w', line)
        if m:
            problems.append(f'{path}:{ln}: handler with parameters: {src.split(chr(10))[ln-1].strip()}')
        # SetPoint shorthand: second argument must be a frame, not a number
        for m in re.finditer(r':SetPoint\(\s*"\w+"\s*(,\s*([^,)]*))?', line):
            if m.group(1) is None:
                problems.append(f'{path}:{ln}: SetPoint with only a point')
            elif re.match(r'^[-\d(]', m.group(2).strip()):
                problems.append(f'{path}:{ln}: SetPoint shorthand (x, y without a frame)')
        # CreateTexture with a sublevel
        if re.search(r':CreateTexture\([^)]*,[^)]*,', line):
            problems.append(f'{path}:{ln}: CreateTexture sublevel')
    # calling a `local function` above its definition reaches a nil global at runtime
    lines = src.split(chr(10))
    defs = {}
    for i, l in enumerate(lines):
        m = re.match(r'\s*local function (\w+)', l)
        if m: defs.setdefault(m.group(1), i)
    for name, di in defs.items():
        for i, l in enumerate(lines[:di]):
            c = l.split('--')[0]
            if re.search(r'(?<![\w.:])' + name + r'\s*\(', c) and not re.match(r'\s*local function', c):
                problems.append(f'{path}:{i+1}: {name}() is used before its local definition on line {di+1}')
                break
    return problems

if __name__ == '__main__':
    from loopclosures import scan
    root = pathlib.Path(sys.argv[1])
    allp = []
    for p in sorted(root.rglob('*.lua')):
        allp += check(p)
        for ln, line, used in scan(p):
            allp.append(f'{p}:{ln}: closure uses loop variable {", ".join(used)} (shared and nil after the loop in Lua 5.0): {line}')
    print('\n'.join(allp) if allp else 'clean')
    print(len(allp), 'problems')
