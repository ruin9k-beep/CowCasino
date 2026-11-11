# Slot math model: exact line and scatter returns, simulated free spins.
import random, itertools, math, sys
STRIPS = [
 ["cherry","seven","bell","plum","cherry","lemon","orange","plum","orange","cherry","bar","lemon","orange","lemon","plum","lemon","bell","plum","lemon","cherry","lemon","cherry","orange","bell","cherry","bar","orange"],
 ["cherry","lemon","bell","lemon","plum","seven","orange","bar","cherry","bell","plum","orange","cherry","lemon","plum","cherry","plum","orange","lemon","cherry","orange","cherry","lemon","bar","lemon","bell","orange"],
 ["cherry","seven","orange","cherry","lemon","plum","lemon","bell","lemon","plum","orange","lemon","plum","cherry","bar","bell","cherry","bell","plum","bar","lemon","orange","lemon","cherry","orange","cherry","orange"],
 ["plum","cherry","lemon","orange","plum","cherry","orange","seven","bell","cherry","lemon","plum","cherry","plum","bell","bar","orange","cherry","lemon","bar","lemon","bell","orange","lemon","cherry","orange","lemon"],
 ["seven","plum","lemon","cherry","lemon","bar","orange","lemon","cherry","bell","lemon","orange","cherry","lemon","cherry","plum","bell","orange","plum","cherry","bell","cherry","orange","plum","lemon","bar","orange"],
]
PAYS_5 = dict(seven={3:75,4:300,5:2000}, bar={3:40,4:150,5:600}, bell={3:30,4:80,5:300}, plum={3:15,4:50,5:150},
              orange={3:14,4:35,5:100}, lemon={3:10,4:25,5:75}, cherry={2:6,3:15,4:40,5:100})
PAYS_3 = dict(seven={3:750}, bar={3:200}, bell={3:80}, plum={3:50}, orange={3:25}, lemon={3:10}, cherry={2:3,3:15})

def build(wilds, scatters, wild_from=2, scatter_reels=(1, 2, 3, 4, 5)):
    out = []
    for r, s in enumerate(STRIPS):
        s = list(s)
        n = len(s)
        add = []
        if r + 1 >= wild_from: add += ["wild"] * wilds
        if r + 1 in scatter_reels: add += ["scatter"] * scatters
        # spread the additions evenly
        for k, sym in enumerate(add):
            pos = int((k + 0.5) * len(s) / len(add)) + r * 3
            s.insert(pos % len(s), sym)
        out.append(s)
    return out

def line_rtp(strips, reels, pays, scale, wm):
    Em = sum(p * m for m, p in wm)
    tot = 0
    for S in pays:
        p1 = strips[0].count(S) / len(strips[0])
        prob = p1
        for c in range(2, reels + 1):
            st = strips[c - 1]
            e = (st.count(S) + st.count("wild") * Em) / len(st)
            prob *= e
            stop = 1.0
            if c < reels:
                nx = strips[c]
                stop = 1 - (nx.count(S) + nx.count("wild")) / len(nx)
            pay = pays[S].get(c, 0) * scale
            tot += prob * stop * pay
    return tot

def scatter_dist(strips, reels, rows):
    ps = [min(1, strips[r].count("scatter") * rows / len(strips[r])) for r in range(reels)]
    dist = {0: 1.0}
    for p in ps:
        nd = {}
        for k, v in dist.items():
            nd[k] = nd.get(k, 0) + v * (1 - p)
            nd[k + 1] = nd.get(k + 1, 0) + v * p
        dist = nd
    return dist

def spin(strips, reels, rows, lines, pays, scale, wm):
    stops = [random.randrange(len(strips[r])) for r in range(reels)]
    view = [[strips[r][(stops[r] + row) % len(strips[r])] for row in range(rows)] for r in range(reels)]
    mults = [[(random.choices([m for m, p in wm], [p for m, p in wm])[0] if view[r][row] == "wild" else 1) for row in range(rows)] for r in range(reels)]
    total = 0
    for line in lines:
        first = view[0][line[0]]
        if first not in pays: continue
        c, m = 1, 1
        for r in range(1, reels):
            s = view[r][line[r]]
            if s == first or s == "wild":
                c += 1; m *= mults[r][line[r]]
            else: break
        total += pays[first].get(c, 0) * scale * m
    nsc = sum(1 for r in range(reels) for row in range(rows) if view[r][row] == "scatter")
    return total, nsc

def free_round(n0, strips, reels, rows, lines, pays, scale, wm, freeN, scPay, maxMult):
    left, mult, won = n0, 1, 0.0
    nl = len(lines)
    while left > 0:
        left -= 1
        line_win, nsc = spin(strips, reels, rows, lines, pays, scale, wm)
        w = line_win / nl + scPay.get(nsc, 0)      # in total bets
        if w > 0:
            won += w * mult
            mult = min(maxMult, mult + 1)
        left += freeN.get(nsc, 0) and 5 or 0       # retrigger: +5
    return won
NEW5 = dict(seven={3:20,4:80,5:500}, bar={3:10,4:40,5:150}, bell={3:8,4:20,5:80}, plum={3:4,4:13,5:40},
            orange={3:4,4:9,5:25}, lemon={3:3,4:6,5:20}, cherry={2:1,3:4,4:10,5:25})
NEW3 = dict(seven={3:250}, bar={3:65}, bell={3:26}, plum={3:16}, orange={3:8}, lemon={3:3}, cherry={2:1,3:5})
