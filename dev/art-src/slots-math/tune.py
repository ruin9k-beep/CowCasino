from model import *
import random
random.seed(7)
L5x4 = [[1,1,1,1,1],[2,2,2,2,2],[3,3,3,3,3],[4,4,4,4,4],[1,2,3,2,1],[4,3,2,3,4],[2,3,4,3,2],[3,2,1,2,3],[2,1,1,1,2],[3,4,4,4,3]]
L5x5 = [[1,1,1,1,1],[2,2,2,2,2],[3,3,3,3,3],[4,4,4,4,4],[5,5,5,5,5],[1,2,3,2,1],[5,4,3,4,5],[2,3,4,3,2],[4,3,2,3,4],[1,2,3,4,5],[5,4,3,2,1],[2,1,1,1,2],[4,5,5,5,4],[3,2,2,2,3],[3,4,4,4,3]]
L3 = [[1,1,1],[2,2,2],[3,3,3],[1,2,3],[3,2,1]]
z = lambda L: [[x - 1 for x in l] for l in L]
WM = [(2, .6), (3, .3), (5, .1)]
def report(name, reels, rows, lines, pays, scale, wilds, freeN, scPay, maxMult, rounds=4000, scat=1, sreels=(1,2,3,4,5)):
    strips = build(wilds, scat, 2, sreels)[:reels]
    Lr = line_rtp(strips, reels, pays, scale, WM)
    d = scatter_dist(strips, reels, rows)
    sc = sum(p * scPay.get(k, 0) for k, p in d.items())
    trig = sum(p for k, p in d.items() if freeN.get(k))
    fv = 0
    for k, p in d.items():
        if freeN.get(k):
            v = sum(free_round(freeN[k], strips, reels, rows, z(lines), pays, scale, WM, freeN, scPay, maxMult) for _ in range(rounds)) / rounds
            fv += p * v
    print(f"{name}: lines {Lr:.4f} scatter {sc:.4f} trigger 1 in {1/trig:.0f}  free {fv:.4f}  TOTAL {Lr+sc+fv:.4f}")
import sys
exec(sys.argv[1])
