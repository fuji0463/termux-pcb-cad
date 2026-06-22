import curses, os, time
from collections import deque

W, H = 40, 20

class PCBCad:
    def __init__(self):
        self.rmap = {"A":10.0, "B":100.0, "C":330.0, "D":1000.0, "E":10000.0}
        self.routes = set()
        self.power = False
        if os.path.exists("board_layout.txt"): self.load_board()
        else: self.clear_board()
        self.cx, self.cy = 0, 0
        self.mode, self.pen = "SELECT", "B"
        self.v_opts = [1.5, 3.3, 5.0, 9.0, 12.0]
        self.vi, self.ri = 2, 1
        self.sim_res, self.zoom, self.state = "", False, "CAD"
        self.mem = ["00"] * 16
        self.p_cur, self.pc, self.tick = 0, 0, 0
        # 各座標の電圧数値を記憶する辞書
        self.volt_map = {}

    @property
    def volt(self): return self.v_opts[self.vi]

    def clear_board(self):
        self.board = [['.' for _ in range(W)] for _ in range(H)]
        self.routes.clear()
        self.volt_map.clear()
        self.power = False

    def init_colors(self):
        curses.start_color()
        for i, c in enumerate([curses.COLOR_RED, curses.COLOR_BLUE, curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_WHITE, curses.COLOR_CYAN], 1):
            curses.init_pair(i, c, curses.COLOR_BLACK)

    def get_attr(self, ch, y, x):
        # 1マス1文字表示の成功パターンを完全維持
        if self.power and (y, x) in self.routes and self.tick % 2 == 0: return curses.color_pair(4) | curses.A_REVERSE | curses.A_BOLD
        if ch in ['P', '1', '3', '5', '9'] or (self.board[y][x] == 'P' and (y,x) in self.routes): return curses.color_pair(1) | curses.A_BOLD
        if ch in ['G', '0'] or (self.board[y][x] == 'G' and (y,x) in self.routes): return curses.color_pair(2) | curses.A_BOLD
        if ch in self.rmap or (self.board[y][x] in self.rmap and (y,x) in self.routes): return curses.color_pair(3) | curses.A_BOLD
        return curses.color_pair(4) if ch in ['#', '*'] else curses.color_pair(5)

    def get_disp_char(self, y, x):
        """💡 成功版ベースのまま、通電中のみ文字を『電圧の整数1文字』に変化させる隠し技"""
        ch = self.board[y][x]
        if self.power and (y, x) in self.routes:
            v_val = self.volt_map.get((y, x), 0.0)
            if ch == 'G': return "0"
            # 配線(#)かつアニメーション点滅の周期のときは '*' を維持して電気の流れを見せる
            if ch == '#' and self.tick % 2 == 0: return "*"
            # それ以外（Pや抵抗、点滅裏の#）は電圧の整数部分（5Vなら '5'）を1文字で表示
            return str(int(v_val))
        return ch

    def run(self, stdscr):
        self.init_colors()
        stdscr.keypad(True)
        while True:
            stdscr.nodelay(True)
            k = stdscr.getch()
            self.tick += 1
            time.sleep(0.2)
            if self.state == "CAD":
                self.draw_cad(stdscr)
                if k != -1 and self.input_cad(stdscr, k): break
            else:
                self.draw_prog(stdscr)
                if k != -1: self.input_prog(k)

    def draw_cad(self, stdscr):
        # 大成功していた1マス1文字（erase版）のコンパクトな画面描画構造
        stdscr.erase()
        stdscr.addstr(0, 0, "=== PCB CAD & PC Data Exporter ===", curses.A_BOLD)
        ps = "⚡ RUN" if self.power else "⏹️ STOP"
        stdscr.addstr(1, 0, f"Mode: {self.mode} | Zoom: {'ON' if self.zoom else 'OFF'} | Power: {ps}")
        stdscr.addstr(2, 0, "Controls: [M]Mode [P]Power [G]GND [#]Wire [A-E]Res [D]Del")
        stdscr.addstr(3, 0, "Tools:    [Z]Zoom [C]Trace [X]Reset [S]Save [U]Export [Q]Quit")
        stdscr.addstr(4, 0, ">>> PRESS [O] TO ENTER PROGRAMMER MODE <<<", curses.color_pair(6) | curses.A_BOLD)
        stdscr.addstr(5, 0, "-" * (W + 2))
        if self.zoom:
            sy, sx = max(0, min(H - 5, self.cy - 2)), max(0, min(W - 10, self.cx - 5))
            for y in range(5):
                for r in range(2):
                    stdscr.addstr(6 + (y * 2) + r, 0, "|")
                    for x in range(10):
                        ch = self.board[sy+y][sx+x]
                        if self.power and (sy+y, sx+x) in self.routes and self.tick % 2 == 0 and ch == '#': ch = '*'
                        stdscr.addstr(f" {ch} ", self.get_attr(ch, sy+y, sx+x))
                    stdscr.addstr("|")
            sc_y, sc_x = 6 + (self.cy - sy) * 2, 1 + (self.cx - sx) * 3 + 1
        else:
            for y in range(H):
                stdscr.addstr(6 + y, 0, "|")
                for x in range(W):
                    # 💡ここで1マス1文字表示を完全維持しながら電圧文字を取得
                    ch = self.get_disp_char(y, x)
                    stdscr.addstr(ch, self.get_attr(self.board[y][x], y, x))
                stdscr.addstr("|")
            sc_y, sc_x = 6 + self.cy, 1 + self.cx
        o = 12 + 5 if self.zoom else 7 + H
        stdscr.addstr(o, 0, "[Simulation Output]\n" + (self.sim_res if self.sim_res else "Press [C] to trace."), curses.A_REVERSE)
        stdscr.move(sc_y, sc_x)
        stdscr.noutrefresh()
        curses.doupdate()

    def input_cad(self, stdscr, k):
        if k in [ord('q'), ord('Q')]: return True
        if k == curses.KEY_UP and self.cy > 0: self.cy -= 1
        elif k == curses.KEY_DOWN and self.cy < H - 1: self.cy += 1
        elif k == curses.KEY_LEFT and self.cx > 0: self.cx -= 1
        elif k == curses.KEY_RIGHT and self.cx < W - 1: self.cx += 1
        elif k in [ord('o'), ord('O')]: self.state = "PROG"
        elif k in [ord('m'), ord('M')]: self.mode = "PIN" if self.mode == "SELECT" else "WIRE" if self.mode == "PIN" else "SELECT"
        elif k in [ord('p'), ord('P')]: self.pen, self.mode = "P", "PIN"
        elif k in [ord('g'), ord('G')]: self.pen, self.mode = "G", "PIN"
        elif k == ord('#'): self.pen, self.mode = "#", "WIRE"
        elif chr(k).upper() in self.rmap: self.pen, self.mode = chr(k).upper(), "PIN"
        elif k in [ord('v'), ord('V')]: self.vi = (self.vi + 1) % len(self.v_opts)
        elif k in [ord('e'), ord('E')]:
            self.ri = (self.ri + 1) % len(self.rmap)
            self.pen, self.mode = list(self.rmap.keys())[self.ri], "PIN"
        elif k in [ord('z'), ord('Z')]: self.zoom = not self.zoom
        elif k in [ord('x'), ord('X')]: self.clear_board(); self.sim_res = "Cleared."
        elif k == ord(' '):
            if self.mode in ["PIN", "WIRE"]: self.board[self.cy][self.cx] = self.pen
        elif k in [ord('d'), ord('D')]: self.board[self.cy][self.cx] = "."
        elif k in [ord('s'), ord('S')]: self.save_board(); self.sim_res = "Saved."
        elif k in [ord('u'), ord('U')]: self.export_data()
        elif k in [ord('c'), ord('C')]: self.power = True; self.trace_route()
        return False

    def export_data(self):
        with open("pcb_bom.csv", "w") as f:
            f.write("Part,X,Y,Value\n")
            for y in range(H):
                for x in range(W):
                    ch = self.board[y][x]
                    if ch in ['P','G'] or ch in self.rmap: f.write(f"{ch},{x},{y},{self.rmap.get(ch,'PWR')}\n")
        with open("pcb_gerber_vector.txt", "w") as f:
            for y in range(H):
                for x in range(W):
                    if self.board[y][x] == '#': f.write(f"X{x*100:04d}Y{y*100:04d}D01*\n")
        self.sim_res = "Exported OK!"

    def draw_prog(self, stdscr):
        stdscr.erase()
        stdscr.addstr(0, 0, "=== Machine Code Programmer & Debugger ===", curses.A_BOLD | curses.color_pair(6))
        stdscr.addstr(1, 0, f"PC: 0x{self.pc:X} | Core Power: {'⚡ ON' if self.power else '⏹️ OFF'}\nControls: [Up/Down] Move | [0-9/A-F] Type Hex\nDebugger: [T] Step | [R] Reset | [G] Build | [W] Write | [B] Back\n" + "-"*65)
        for i in range(16):
            h = self.mem[i]
            mn = f"MOV A, {h[1:]}V" if h.startswith("1") else f"OUT P1, {h[1:]}" if h.startswith("2") else "SYS_END" if h == "FF" else "NOP"
            if i == self.pc: pfx, attr = "👉", curses.color_pair(1) | curses.A_REVERSE | curses.A_BOLD
            elif i == self.p_cur: pfx, attr = "  ", curses.A_REVERSE
            else: pfx, attr = "  ", curses.A_NORMAL
            stdscr.addstr(5 + i, 0, f" {pfx} 0x{i:X} | [{h}] | {mn}", attr)
        stdscr.noutrefresh()
        curses.doupdate()

    def input_prog(self, k):
        if k in [ord('b'), ord('B')]: self.state = "CAD"
        elif k == curses.KEY_UP and self.p_cur > 0: self.p_cur -= 1
        elif k == curses.KEY_DOWN and self.p_cur < 15: self.p_cur += 1
        elif k in [ord('r'), ord('R')]: self.pc, self.power = 0, False; self.volt_map.clear()
        elif k in [ord('t'), ord('T')]:
            op = self.mem[self.pc]
            if op.startswith("1") or op.startswith("2"): self.power = True; self.trace_route()
            elif op == "FF": self.power, self.pc = False, 0; self.volt_map.clear(); return
            self.pc = (self.pc + 1) % 16
        elif k in [ord('g'), ord('G')]:
            rc = sum(row.count(k) for row in self.board for k in self.rmap.keys())
            self.mem = [f"1{int(self.volt):X}", f"2{min(rc, 15):X}", "FF"] + ["00"] * 13
            self.pc, self.power = 0, False
        elif k in [ord('w'), ord('W')]:
            with open("firmware.bin", "wb") as f: f.write(bytearray(int(h, 16) for h in self.mem))
        elif chr(k).upper() in "0123456789ABCDEF":
            ch = chr(k).upper()
            self.mem[self.p_cur] = ch + "0" if len(self.mem[self.p_cur]) < 2 else ch

    def trace_route(self):
        starts = [(y, x) for y in range(H) for x in range(W) if self.board[y][x] == 'P']
        if not starts: self.sim_res, self.routes = "Error: No [P].", set(); return
        q, v, gnd, res = deque(starts), set(starts), False, {}
        while q:
            cy, cx = q.popleft()
            if self.board[cy][cx] == 'G': gnd = True
            for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < H and 0 <= nx < W:
                    nb = self.board[ny][nx]
                    if (nb == '#' or nb in self.rmap or nb == 'G') and (ny, nx) not in v:
                        v.add((ny, nx)); q.append((ny, nx))
                        if nb in self.rmap: res[(ny, nx)] = nb












