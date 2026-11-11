"""Find (and optionally fix) closures created inside for-loops that use the loop
variables. In Lua 5.0 those variables are shared by every closure from the loop
and are nil after the loop ends; the fix is `local v = v` at the top of the body."""
import re, sys, pathlib

FOR = re.compile(r'^(\s*)for\s+(.+?)\s+(?:=|in)\s.*\bdo\s*$')

def loop_vars(head):
    return [v.strip() for v in head.split(',') if v.strip() and v.strip() != '_']

def body_end(lines, i, indent):
    for j in range(i + 1, len(lines)):
        if lines[j].startswith(indent + 'end') and len(lines[j]) - len(lines[j].lstrip()) == len(indent):
            return j
    return None

def scan(path, fix=False):
    lines = pathlib.Path(path).read_text().split('\n')
    found, inserts = [], []
    for i, line in enumerate(lines):
        m = FOR.match(line)
        if not m:
            continue
        indent, vars_ = m.group(1), loop_vars(m.group(2))
        j = body_end(lines, i, indent)
        if j is None:
            continue
        body = '\n'.join(lines[i + 1:j])
        if 'function' not in body:
            continue
        used = []
        for v in vars_:
            # does any function inside the body mention v?
            for fm in re.finditer(r'function\s*[\w\.:]*\(', body):
                tail = body[fm.end():]
                if re.search(r'\b' + re.escape(v) + r'\b', tail):
                    used.append(v)
                    break
        already = re.match(r'\s*local\s+' + r'\s*,\s*'.join(map(re.escape, used)) + r'\s*=', lines[i + 1]) if used else None
        if used and not already:
            found.append((i + 1, line.strip(), used))
            inserts.append((i + 1, indent + '    local ' + ', '.join(used) + ' = ' + ', '.join(used) + '   -- own copy for closures (Lua 5.0)'))
    if fix and inserts:
        for at, text in reversed(inserts):
            lines.insert(at, text)
        pathlib.Path(path).write_text('\n'.join(lines))
    return found

if __name__ == '__main__':
    root, fix = pathlib.Path(sys.argv[1]), '--fix' in sys.argv
    total = 0
    for p in sorted(root.rglob('*.lua')):
        for ln, line, used in scan(p, fix):
            total += 1
            print(f'{p.relative_to(root)}:{ln}: {line}   uses {", ".join(used)}')
    print(total, 'loops', 'fixed' if fix else 'found')
