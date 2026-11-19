"""Generates the hardware-store diagrams of Chapter IV as draw.io files and PNGs.

Run from the repository root:

    python3 docs/diagrams/generate_diagrams.py            # .drawio + .png
    python3 docs/diagrams/generate_diagrams.py --no-png   # .drawio only

The flowcharts, context diagram, DFD and use case diagram are described below
in code; the ERD is read from backend_django/apps/*/models.py, so it always
matches the database. PNGs need the draw.io desktop app (DRAWIO env var, or
the default macOS install path). The style matches the construction team's
diagrams in ../project/docs/diagrams/ so both halves of Chapter IV look alike.
"""

import ast
import html
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DRAWIO = os.environ.get('DRAWIO', '/Applications/draw.io.app/Contents/MacOS/draw.io')

# Sizes are for the printed page: Word scales every figure to the text width,
# so text under ~13 and 1 px lines come out too small to read.
_SHAPE = 'whiteSpace=wrap;html=1;fontStyle=1;strokeWidth=2;'
STYLES = {
    'box': f'rounded=0;{_SHAPE}fontSize=14;',
    'terminal': f'ellipse;{_SHAPE}fontSize=15;',
    'dec': f'rhombus;{_SHAPE}fontSize=14;',
    # The slanted sides eat into the text box, hence the side spacing.
    'io': ('shape=parallelogram;perimeter=parallelogramPerimeter;fixedSize=1;size=14;'
           f'spacingLeft=14;spacingRight=14;{_SHAPE}fontSize=14;'),
    'entity': f'rounded=0;{_SHAPE}fontSize=15;',
    'ctx_entity': f'rounded=0;{_SHAPE}fontSize=18;',
    'system': f'rounded=1;{_SHAPE}fontSize=18;',
    'process': f'rounded=1;arcSize=12;{_SHAPE}fontSize=14;',
    'store': ('shape=partialRectangle;right=0;fillColor=none;align=left;spacingLeft=10;'
              f'{_SHAPE}fontSize=14;'),
    'actor': ('shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;'
              f'{_SHAPE}fontSize=14;'),
    'usecase': f'ellipse;{_SHAPE}fontSize=13;',
    'boundary': ('rounded=0;fillColor=none;verticalAlign=top;spacingTop=8;'
                 f'{_SHAPE}fontSize=16;'),
}
TEXT = ('text;html=1;whiteSpace=wrap;fontSize={size};fontStyle=1;verticalAlign=middle;'
        'align={align};')
ARROW = ('html=1;rounded=0;endArrow=block;endFill=1;strokeWidth=2;fontSize=12;fontStyle=1;'
         'labelBackgroundColor=#ffffff;')
LINE = 'html=1;rounded=0;endArrow=none;strokeWidth=1.5;'


def _label(text):
    """A label for an html=1 cell: escaped, with newlines as line breaks."""
    return html.escape(text).replace('\n', '&lt;br&gt;')


class Diagram:
    """A draw.io page: shapes keyed by id, plus edges between them."""

    def __init__(self, name):
        self.name = name
        self.cells = []
        self.geo = {}
        self.count = 1

    def _next(self, prefix):
        self.count += 1
        return f'{prefix}{self.count}'

    def node(self, label, x, y, w=170, h=55, kind='box'):
        cid = self._next('n')
        self.geo[cid] = (x, y, w, h)
        self.cells.append(
            f'<mxCell id="{cid}" value="{_label(label)}" style="{STYLES[kind]}" '
            f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" '
            f'height="{h}" as="geometry"/></mxCell>')
        return cid

    def text(self, label, x, y, w, h=20, align='center', size=12):
        cid = self._next('t')
        self.cells.append(
            f'<mxCell id="{cid}" value="{_label(label)}" '
            f'style="{TEXT.format(align=align, size=size)}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')

    def raw(self, xml):
        self.cells.append(xml)

    def edge(self, src, dst, label='', pts=(), exit=None, entry=None, style=ARROW):
        """An arrow; exit/entry are (x, y) fractions of the source/target box."""
        cid = self._next('e')
        extra = ''
        if exit:
            extra += f'exitX={exit[0]:.4f};exitY={exit[1]:.4f};exitDx=0;exitDy=0;'
        if entry:
            extra += f'entryX={entry[0]:.4f};entryY={entry[1]:.4f};entryDx=0;entryDy=0;'
        points = ''.join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in pts)
        array = f'<Array as="points">{points}</Array>' if pts else ''
        self.cells.append(
            f'<mxCell id="{cid}" value="{html.escape(label)}" style="{style}{extra}" '
            f'edge="1" parent="1" source="{src}" target="{dst}">'
            f'<mxGeometry relative="1" as="geometry">{array}</mxGeometry></mxCell>')

    # Geometry helpers -----------------------------------------------------

    def cx(self, cid):
        x, _, w, _ = self.geo[cid]
        return x + w / 2

    def top(self, cid):
        return self.geo[cid][1]

    def bottom(self, cid):
        _, y, _, h = self.geo[cid]
        return y + h

    def mid_y(self, cid):
        _, y, _, h = self.geo[cid]
        return y + h / 2

    def frac_y(self, cid, abs_y):
        _, y, _, h = self.geo[cid]
        return (abs_y - y) / h

    def save(self):
        body = ''.join(self.cells)
        xml = (f'<mxfile host="drawio"><diagram name="{self.name}"><mxGraphModel grid="0" '
               f'page="0" background="#ffffff"><root><mxCell id="0"/>'
               f'<mxCell id="1" parent="0"/>{body}</root></mxGraphModel></diagram></mxfile>')
        path = HERE / f'{self.name}.drawio'
        path.write_text(xml, encoding='utf-8')
        return path


# Flowcharts ---------------------------------------------------------------

GAP = 32


def stack(d, cx, y, steps, w=190):
    """Places steps top to bottom around centre cx; returns ids and the next y."""
    ids = []
    for kind, label in steps:
        width, height = (190, 100) if kind == 'dec' else (w + (50 if kind == 'io' else 0), 62)
        ids.append(d.node(label, cx - width / 2, y, width, height, kind))
        y += height + GAP
    return ids, y


def chain(d, ids):
    for a, b in zip(ids, ids[1:]):
        d.edge(a, b, exit=(0.5, 1), entry=(0.5, 0))


def header(d, cx, dashboard, extra=()):
    """Start, Login, [extra steps], the dashboard and the Task? decision."""
    ids, _ = stack(d, cx, 40, [('box', 'Login'), *extra, ('box', dashboard),
                               ('dec', 'Task?')], w=230)
    start = d.node('Start', cx - 60, -40, 120, 50, 'terminal')
    chain(d, [start, *ids])
    return ids


def branches(d, task, columns, y):
    """Fans the Task? decision out to one column per task, each labelled."""
    bus = d.bottom(task) + 25
    firsts = []
    for label, cx, steps in columns:
        ids, _ = stack(d, cx, y, steps)
        d.edge(task, ids[0], pts=[(d.cx(task), bus), (cx, bus)],
               exit=(0.5, 1), entry=(0.5, 0))
        d.text(f'[{label}]', cx + 6, y - 26, 190, 18, 'left')
        firsts.append(ids)
    return firsts


def finish(d, cx, lasts, extra_lanes=()):
    """Every column's last step joins one line into End."""
    lowest = max(d.bottom(i) for i in lasts)
    join = lowest + 35
    end = d.node('End', cx - 60, join + 35, 120, 50, 'terminal')
    for last in lasts:
        d.edge(last, end, pts=[(d.cx(last), join), (cx, join)],
               exit=(0.5, 1), entry=(0.5, 0))
    for src, lane_x, src_exit in extra_lanes:
        y = d.geo[src][1] + d.geo[src][3] * src_exit[1]
        d.edge(src, end, pts=[(lane_x, y), (lane_x, join), (cx, join)],
               exit=src_exit, entry=(0.5, 0))
    return end


def cashier_flowchart():
    d = Diagram('fig7-cashier-flowchart')
    cx = 770
    login, shift_q, dash, task = header(
        d, cx, 'View POS (New transaction)', [('dec', 'Shift open?')])
    # The till refuses a sale until the cashier opens a shift (open-shift gate).
    open_shift = d.node('Input opening cash float, open shift', cx + 160,
                        d.top(shift_q) + 19, 290, 62, 'io')
    d.edge(shift_q, open_shift, '[No]', exit=(1, 0.5), entry=(0, 0.5))
    d.edge(open_shift, dash, pts=[(d.cx(open_shift), d.mid_y(dash))],
           exit=(0.5, 1), entry=(1, 0.5))
    d.text('[Yes]', cx + 6, d.bottom(shift_q) + 4, 50, 18, 'left')

    y = d.bottom(task) + 80
    sale, release, payment, ret, close = branches(d, task, [
        ('Sale', 120, [('box', 'Scan barcode or search items'),
                       ('io', 'Input quantity and unit'),
                       ('box', 'Select walk-in or named customer'),
                       ('io', 'Input payment method and amount'),
                       ('dec', 'Paid in full?'),
                       ('box', 'Record sale, deduct stock (FIFO)'),
                       ('box', 'Print receipt')]),
        ('Release materials', 600, [('io', 'Scan slip QR or type token'),
                                    ('dec', 'Token valid and unused?'),
                                    ('box', 'Review requested items'),
                                    ('io', 'Input release quantities'),
                                    ('box', 'Deduct stock, log project utang'),
                                    ('box', 'Mark token used')]),
        ('Record payment', 880, [('box', 'Select customer receivable'),
                                 ('io', 'Input amount paid'),
                                 ('box', 'Update balance (Partial or Paid)')]),
        ('Return', 1150, [('box', 'Find original sale'),
                          ('io', 'Input returned items'),
                          ('box', 'Restock, reduce utang first, then refund')]),
        ('End shift', 1420, [('io', 'Input counted cash'),
                             ('box', 'Close shift, view Z-reading')]),
    ], y)

    # Sale: the two payment questions.
    chain(d, sale[:5])
    paid_q, record, receipt = sale[4], sale[5], sale[6]
    d.edge(paid_q, record, '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    chain(d, [record, receipt])
    named = d.node('Named customer?', 262, d.top(paid_q), 190, 100, 'dec')
    d.edge(paid_q, named, '[No]', exit=(1, 0.5), entry=(0, 0.5))
    utang = d.node('Log balance as utang', 262, d.top(record), 190, 62)
    d.edge(named, utang, '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    d.edge(utang, record, exit=(0, 0.5), entry=(1, 0.5))
    # Walk-in customers cannot owe: the server refuses (WALK_IN_CANNOT_OWE).
    pay_step = sale[3]
    d.edge(named, pay_step, '[No] Collect full payment',
           pts=[(d.cx(named), d.mid_y(pay_step))], exit=(0.5, 0), entry=(1, 0.5))

    # Release: a bad token stops at the counter.
    verify_q = release[1]
    chain(d, release[:2])
    d.edge(verify_q, release[2], '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    chain(d, release[2:])
    chain(d, payment)
    chain(d, ret)
    chain(d, close)

    finish(d, cx, [receipt, release[-1], payment[-1], ret[-1], close[-1]],
           extra_lanes=[(verify_q, 735, (1, 0.5))])
    # The till shows why the token failed and the release stops there.
    d.text('[No]', 698, d.mid_y(verify_q) - 22, 40, 18, 'left')
    return d


def stock_manager_flowchart():
    d = Diagram('fig8-stock-manager-flowchart')
    cx = 795
    _, dash, task = header(d, cx, 'View inventory dashboard and low-stock alerts')
    y = d.bottom(task) + 80
    restock, catalog, adjust, supplier, reports = branches(d, task, [
        ('Restock', 120, [('dec', 'Product in catalog?'),
                          ('io', 'Input purchase order (supplier, items, cost)'),
                          ('io', 'Receive delivery: quantities, DR no.'),
                          ('box', 'Process receipt: new batches, stock up'),
                          ('box', 'Print barcode labels')]),
        ('Catalog', 660, [('io', 'Input product, variants, units, prices'),
                          ('box', 'Barcode assigned (factory or QB code)'),
                          ('box', 'Print barcode labels')]),
        ('Adjust stock', 930, [('box', 'Select item'),
                               ('io', 'Input type, quantity, remarks'),
                               ('box', 'Update stock, log movement')]),
        ('Suppliers', 1200, [('io', 'Input supplier or category details'),
                            ('box', 'Save supplier or category')]),
        ('Reports', 1470, [('box', 'View stock, movements, sales and returns')]),
    ], y)
    exists_q = restock[0]
    d.edge(exists_q, restock[1], '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    add = d.node('Add product, units, barcode', 262, d.top(exists_q) + 19, 250, 62, 'io')
    d.edge(exists_q, add, '[No]', exit=(1, 0.5), entry=(0, 0.5))
    d.edge(add, restock[1], pts=[(d.cx(add), d.mid_y(restock[1]))],
           exit=(0.5, 1), entry=(1, 0.5))
    chain(d, restock[1:])
    for column in (catalog, adjust, supplier):
        chain(d, column)
    finish(d, cx, [restock[-1], catalog[-1], adjust[-1], supplier[-1], reports[-1]])
    return d


def store_manager_flowchart():
    d = Diagram('fig8a-store-manager-flowchart')
    cx = 905
    _, dash, task = header(d, cx, 'View sales dashboard')
    y = d.bottom(task) + 80
    req, quote, recv, ret, rep, staff = branches(d, task, [
        ('Requisition', 120, [('box', 'Review submitted requisition'),
                              ('dec', 'Approve?'),
                              ('box', 'Release token generated'),
                              ('box', 'Print release slip (QR)'),
                              ('box', 'Hand slip to foreman')]),
        ('Quotation', 580, [('io', 'Input quotation: customer, items'),
                            ('dec', 'Customer accepts?'),
                            ('box', 'Convert to sales order')]),
        ('Receivables', 880, [('box', 'View receivables and aging'),
                              ('io', 'Record payment')]),
        ('Unlinked return', 1150, [('io', 'Input returned items (no receipt)'),
                                  ('box', 'Restock and refund')]),
        ('Reports', 1420, [('io', 'Select report and period'),
                           ('box', 'View sales, inventory, movements, requisitions')]),
        ('Staff', 1690, [('io', 'Input staff account or role change'),
                         ('box', 'Save staff account')]),
    ], y)
    chain(d, req[:2])
    approve_q = req[1]
    d.edge(approve_q, req[2], '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    chain(d, req[2:])
    reject = d.node('Reject requisition', 262, d.top(approve_q) + 19, 190, 62)
    d.edge(approve_q, reject, '[No]', exit=(1, 0.5), entry=(0, 0.5))
    chain(d, quote[:2])
    accept_q = quote[1]
    d.edge(accept_q, quote[2], '[Yes]', exit=(0.5, 1), entry=(0.5, 0))
    for column in (recv, ret, rep, staff):
        chain(d, column)
    finish(d, cx, [req[-1], reject, quote[-1], recv[-1], ret[-1], rep[-1], staff[-1]],
           extra_lanes=[(accept_q, 720, (1, 0.5))])
    d.text('[No]', 683, d.mid_y(accept_q) - 22, 40, 18, 'left')
    return d


# Context diagram ----------------------------------------------------------

def context_diagram():
    d = Diagram('fig11-pos-context-diagram')
    system = d.node('POS and Inventory System', 800, 460, 400, 540, 'system')
    top = d.node('Store Cashier', 880, 30, 240, 95, 'ctx_entity')
    bottom = d.node('Store Manager', 880, 1335, 240, 95, 'ctx_entity')
    left = [d.node('Site Foreman', 30, 460, 270, 95, 'ctx_entity'),
            d.node('Construction Project Management System', 30, 905, 270, 95, 'ctx_entity')]
    right = [d.node('System Administrator', 1700, 460, 270, 95, 'ctx_entity'),
             d.node('Stock Manager', 1700, 905, 270, 95, 'ctx_entity')]

    def vertical(entity, down_label, up_label, entity_above):
        # Two vertical arrows: x=970 flows toward the system, x=1035 away (or reverse).
        ex_top, ex_bottom = (d.bottom(entity), d.top(system)) if entity_above else \
            (d.top(entity), d.bottom(system))
        frac_in = 970 - 880
        if entity_above:
            d.edge(entity, system, pts=[], exit=(frac_in / 240, 1), entry=(170 / 400, 0))
            d.edge(system, entity, exit=(235 / 400, 0), entry=(155 / 240, 1))
            d.text(down_label, 560, 240, 395, 70, 'right', size=16)
            d.text(up_label, 1050, 240, 400, 70, 'left', size=16)
        else:
            d.edge(entity, system, exit=(frac_in / 240, 0), entry=(170 / 400, 1))
            d.edge(system, entity, exit=(235 / 400, 1), entry=(155 / 240, 0))
            d.text(up_label, 560, 1130, 395, 70, 'right', size=16)
            d.text(down_label, 1050, 1130, 400, 70, 'left', size=16)

    vertical(top,
             'Sale items, customer, payments, returns, scanned release tokens, '
             'utang payments, opening float and cash count',
             'Prices and stock, printed receipts, requisition details to release, '
             'Z-reading', True)
    vertical(bottom,
             'Sales, inventory, receivables and requisition reports; printed release '
             'slips (QR)',
             'Requisition approvals, quotations and sales orders, unlinked returns, '
             'staff accounts, report periods', False)

    def side(entity, to_system, from_system, on_left):
        _, ey, _, _ = d.geo[entity]
        y_out, y_in = ey + 25, ey + 72
        rel = lambda y: d.frac_y(system, y)
        if on_left:
            d.edge(system, entity, exit=(0, rel(y_out)), entry=(1, 25 / 95))
            d.edge(entity, system, exit=(1, 72 / 95), entry=(0, rel(y_in)))
            d.text(from_system, 320, y_out - 50, 460, 45, size=16)
            d.text(to_system, 320, y_in + 6, 460, 45, size=16)
        else:
            d.edge(entity, system, exit=(0, 25 / 95), entry=(1, rel(y_out)))
            d.edge(system, entity, exit=(1, rel(y_in)), entry=(0, 72 / 95))
            d.text(to_system, 1220, y_out - 50, 460, 45, size=16)
            d.text(from_system, 1220, y_in + 6, 460, 45, size=16)

    side(left[0], 'Material requisitions: project, items, quantities',
         'Requisition status, release slip (QR token)', True)
    side(left[1], 'Own-store orders: items, quantities, delivery address (API, planned)',
         'Store catalog, prices, fulfillment status (API, planned)', True)
    side(right[0], 'User accounts and roles', 'Audit log, sales and inventory monitoring',
         False)
    side(right[1], 'Products, units, barcodes, purchase orders, deliveries received, '
         'stock adjustments', 'Low-stock alerts, stock levels and movements, barcode '
         'labels', False)
    return d


# Data flow diagram --------------------------------------------------------

def dfd():
    d = Diagram('fig13-pos-dfd')
    # Columns. Every label sits on the short segment next to its own box, and
    # every vertical lane runs PAST the labels, so no line crosses a label.
    EX, EW, EH = 30, 230, 96          # external entities
    PX, PW = 840, 280                 # processes
    PE = PX + PW
    SX, SW, SH = 1420, 300, 60        # data stores
    RX = 1830                         # 6.0 and its outputs
    # Rows are ordered by who talks to them, not by number: the cashier's
    # processes (1, 5) on top, requisitions (4) beside the three parties that
    # drive it, the stock manager's (2, 3) below. Lanes stay short that way.
    rows = {1: (40, 170), 5: (260, 120), 4: (450, 170), 2: (700, 130),
            3: (910, 120), 7: (1120, 120)}
    names = {1: 'Process Sales and Returns', 2: 'Manage Catalog and Stock',
             3: 'Purchase and Receive Goods', 4: 'Process Requisitions and Releases',
             5: 'Manage Collectibles', 7: 'Manage Users and Audit'}
    proc = {n: d.node(f'{n}.0\n{names[n]}', PX, y, PW, h, 'process')
            for n, (y, h) in rows.items()}
    store_rows = {'D1': (2, 'Inventory: products, units, batches, adjustments, alerts'),
                  'D2': (1, 'Sales, Payments and Shifts'),
                  'D3': (3, 'Suppliers and Purchasing'),
                  'D4': (4, 'Requisitions and Release Tokens'),
                  'D5': (5, 'Collectibles (Utang)'),
                  'D6': (7, 'Users and Audit Log')}
    stores = {}
    for key, (row, label) in store_rows.items():
        y = d.mid_y(proc[row]) - SH / 2
        stores[key] = d.node(f'{key} | {label}', SX, y, SW, SH, 'store')
        d.edge(proc[row], stores[key], exit=(1, 0.5), entry=(0, 0.5))

    # Process to a store on another row: (process, store, process y frac,
    # store y frac, label). Lanes are assigned left to right in this order,
    # chosen so no lane passes a label: labels stop short of the second lane,
    # the first one that runs past another flow's exit.
    cross = [(1, 'D5', 0.97, 0.20, 'Utang balance'),
             (4, 'D2', 0.12, 0.85, 'Requisition sale'),
             (4, 'D5', 0.30, 0.80, 'Project utang'),
             (4, 'D1', 0.88, 0.33, 'Deduct released stock'),
             (1, 'D1', 0.85, 0.15, 'Deduct / restock stock'),
             (3, 'D1', 0.25, 0.85, 'New batches')]
    for i, (pn, sk, pf, sf, label) in enumerate(cross):
        lane = 1250 + 26 * i
        y0 = d.geo[proc[pn]][1] + d.geo[proc[pn]][3] * pf
        y1 = d.geo[stores[sk]][1] + SH * sf
        d.edge(proc[pn], stores[sk], pts=[(lane, y0), (lane, y1)], exit=(1, pf),
               entry=(0, sf))
        d.text(label, PE + 4, y0 - 17, min(lane, 1276) - PE - 8, 16, 'left')

    reports = d.node('6.0\nGenerate Reports', RX, 450, 260, 170, 'process')
    # The farther store takes the outer lane, so the two never cross.
    report_lanes = {'D2': 1785, 'D5': 1755, 'D4': 1755, 'D1': 1755, 'D3': 1785}
    for i, key in enumerate(['D2', 'D5', 'D4', 'D1', 'D3']):
        lane = report_lanes[key]
        sy = d.mid_y(stores[key])
        ey = 450 + 30 + i * 27
        d.edge(stores[key], reports, pts=[(lane, sy), (lane, ey)], exit=(1, 0.5),
               entry=(0, (ey - 450) / 170))
    manager_out = d.node('Store Manager', RX + 5, 200, 250, 85, 'entity')
    admin_out = d.node('System Administrator', RX + 5, 800, 250, 85, 'entity')
    d.edge(reports, manager_out, exit=(0.5, 0), entry=(0.5, 1))
    d.edge(reports, admin_out, exit=(0.5, 1), entry=(0.5, 0))
    d.text('Sales, inventory, movement and requisition reports', RX + 140, 310, 210, 60,
           'left')
    d.text('Sales and inventory monitoring', RX + 140, 680, 210, 40, 'left')

    ents = {'cashier': d.node('Store Cashier', EX, 95, EW, EH, 'entity'),
            'foreman': d.node('Site Foreman', EX, 330, EW, EH, 'entity'),
            'manager': d.node('Store Manager', EX, 470, EW, EH, 'entity'),
            'cpms': d.node('Construction Project Management System', EX, 610, EW, EH,
                           'entity'),
            'stock': d.node('Stock Manager', EX, 820, EW, EH, 'entity'),
            'admin': d.node('System Administrator', EX, 1132, EW, EH, 'entity')}
    flows = [  # entity, process, inbound?, label, entity frac, process frac
        ('cashier', 1, True, 'Items, customer, payments, returns', 0.2, 0.40),
        ('cashier', 1, False, 'Receipts, Z-reading', 0.4, 0.70),
        ('cashier', 5, True, 'Utang payments', 0.6, 0.40),
        ('cashier', 4, True, 'Scanned token, release quantities', 0.8, 0.14),
        ('foreman', 4, True, 'Material requisitions', 0.5, 0.30),
        ('manager', 4, True, 'Approve / reject', 0.35, 0.46),
        ('manager', 4, False, 'Release slip (QR token)', 0.65, 0.60),
        ('cpms', 4, True, 'Own-store orders (API, planned)', 0.35, 0.74),
        ('cpms', 4, False, 'Fulfillment status (API, planned)', 0.65, 0.88),
        ('stock', 2, True, 'Products, units, barcodes, adjustments', 0.25, 0.45),
        ('stock', 2, False, 'Low-stock alerts, labels', 0.5, 0.75),
        ('stock', 3, True, 'Purchase orders, deliveries received', 0.75, 0.50),
        ('admin', 7, True, 'Users and roles', 0.35, 0.35),
        ('admin', 7, False, 'Audit log', 0.65, 0.65),
    ]
    # Lanes by flow index, picked so no flow's horizontal crosses another's
    # vertical: of two flows leaving one entity downward, the longer one
    # takes the inner lane; an inbound and an outbound pair, the inbound.
    lanes = {0: 700, 1: 730, 2: 660, 3: 630, 4: 600, 5: 700, 6: 730, 7: 700,
             8: 730, 9: 700, 10: 730, 11: 660, 12: 700, 13: 730}
    for i, (ent, pn, inbound, label, ef, pf) in enumerate(flows):
        e, pr = ents[ent], proc[pn]
        ey = d.geo[e][1] + EH * ef
        py = d.geo[pr][1] + d.geo[pr][3] * pf
        lane = lanes[i]
        if inbound:
            d.edge(e, pr, pts=[(lane, ey), (lane, py)], exit=(1, ef), entry=(0, pf))
        else:
            d.edge(pr, e, pts=[(lane, py), (lane, ey)], exit=(0, pf), entry=(1, ef))
        d.text(label, EX + EW + 4, ey - 17, 600 - EX - EW - 10, 16, 'left')
    return d


# Use case diagram ---------------------------------------------------------

def use_case_diagram():
    d = Diagram('fig5-pos-use-case')
    d.node('Hardware Store Point-of-Sale and Inventory System', 250, 10, 790, 1100,
           'boundary')
    login = d.node('Log in / authenticate', 540, 60, 210, 50, 'usecase')

    def actor(label, x, y):
        return d.node(label, x, y, 44, 76, 'actor')

    cashier = actor('Store Cashier', 100, 315)
    stock = actor('Stock Manager', 100, 785)
    manager = actor('Store Manager', 1150, 285)
    admin = actor('System Administrator', 1150, 640)
    foreman = actor('Site Foreman', 1150, 950)

    def cases(x, y, labels):
        out = []
        for label in labels:
            out.append(d.node(label, x, y, 300, 50, 'usecase'))
            y += 62
        return out

    left_cases = cases(280, 140, [
        'Open and close shift (Z-reading)', 'Process sale (cash, card, GCash, utang)',
        'Print receipt', 'Hold and resume cart', 'Process return',
        'Release materials (scan QR slip)', 'Record utang payment'])
    stock_cases = cases(280, 610, [
        'Manage products, units and barcodes', 'Print barcode labels',
        'Create purchase orders', 'Receive deliveries', 'Adjust stock',
        'View low-stock alerts', 'Manage suppliers and categories'])
    manager_cases = cases(710, 140, [
        'Approve or reject requisitions', 'Print release slip (QR)',
        'Manage quotations and sales orders', 'Process unlinked return',
        'View sales, receivables and reports', 'Manage staff accounts'])
    admin_cases = cases(710, 560, ['Manage users and roles', 'Review audit log',
                                   'Monitor sales and inventory'])
    foreman_cases = cases(710, 965, ['Submit material requisition (API only)'])

    for a, group in ((cashier, left_cases), (stock, stock_cases)):
        for case in group:
            d.edge(a, case, exit=(1, 0.3), entry=(0, 0.5), style=LINE)
    for a, group in ((manager, manager_cases), (admin, admin_cases),
                     (foreman, foreman_cases)):
        for case in group:
            d.edge(a, case, exit=(0, 0.3), entry=(1, 0.5), style=LINE)
    # Login: every app user, along the top of the boundary above the columns.
    for a in (cashier, stock):
        d.edge(a, login, pts=[(60, d.top(a) + 23), (60, 85)], exit=(0, 0.3),
               entry=(0, 0.5), style=LINE)
    for a in (manager, admin):
        d.edge(a, login, pts=[(1235, d.top(a) + 23), (1235, 85)], exit=(1, 0.3),
               entry=(1, 0.5), style=LINE)
    d.text('Admin also has every store function above.', 710, 765, 300, 20)
    return d


# ERD from the Django models ----------------------------------------------

FIELD_TYPES = ('ForeignKey', 'OneToOneField')


def _snake(name):
    # POItem -> PO_ITEM, VariantUOM -> VARIANT_UOM, GoodsReceipt -> GOODS_RECEIPT.
    return re.sub(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])', '_', name).upper()


def read_models():
    """{model: (app, [(kind, column, target)])} from every apps/*/models.py."""
    models = {}
    for path in sorted((ROOT / 'backend_django' / 'apps').glob('*/models.py')):
        tree = ast.parse(path.read_text())
        for node in tree.body:
            if not isinstance(node, ast.ClassDef):
                continue
            bases = {ast.unparse(b) for b in node.bases}
            if not bases & {'models.Model', 'AbstractBaseUser'}:
                continue
            cols = [('PK', 'id', None)]
            for stmt in node.body:
                if not (isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.Call)):
                    continue
                func = ast.unparse(stmt.value.func)
                if not func.startswith('models.'):
                    continue
                name = stmt.targets[0].id
                kind = func.split('.', 1)[1]
                if kind in FIELD_TYPES:
                    arg = stmt.value.args[0] if stmt.value.args else None
                    target = ast.unparse(arg).strip("'\"") if arg is not None else ''
                    target = 'User' if 'AUTH_USER_MODEL' in target else target.split('.')[-1]
                    cols.append(('FK', f'{name}_id', target))
                elif kind.endswith('Field'):
                    cols.append(('', name, None))
            if 'AbstractBaseUser' in bases:
                cols.insert(1, ('', 'password', None))
            models[node.name] = (path.parent.name, cols)
    # Roles are Django's built-in groups (Phase 2), joined to users many-to-many.
    models['Group'] = ('auth', [('PK', 'id', None), ('', 'name (role)', None)])
    models['UserGroups'] = ('auth', [('PK', 'id', None), ('FK', 'user_id', 'User'),
                                     ('FK', 'group_id', 'Group')])
    return models


def erd():
    d = Diagram('pos-erd')
    models = read_models()
    # Related tables side by side, by business area, so relationship lines stay
    # short. A model added later lands in the last column until placed here.
    # Every relationship joins neighbouring columns or one column, so no line
    # crosses a table: the variant hubs sit beside their line-item tables, the
    # line items beside their headers, the headers beside CUSTOMER.
    columns = [
        ['Category', 'Brand', 'Group', 'UserGroups', 'User', 'AuditLog'],
        ['Product', 'Supplier', 'PurchaseOrder'],
        ['ProductVariant', 'UnitOfMeasure', 'POItem', 'GoodsReceipt', 'StockAdjustment',
         'SystemAlert'],
        ['VariantUOM', 'InventoryBatch', 'GoodsReceiptItem', 'SalesItemDeduction',
         'RequisitionItem'],
        ['SalesItem', 'QuotationItem', 'SalesOrderItem', 'HeldCartItem', 'Requisition',
         'MaterialToken'],
        ['SalesTransaction', 'Quotation', 'SalesOrder', 'HeldCart', 'Project'],
        ['Customer', 'CollectibleLedger', 'Payment', 'OfficialReceipt', 'Shift'],
        ['CollectiblePayment', 'DocumentCounter'],
    ]
    placed = {m for column in columns for m in column}
    columns[-1] += sorted(m for m in models if m not in placed)
    width, row_h = 250, 22
    ids = {}
    slots = [(i, name) for i, column in enumerate(columns) for name in column
             if name in models]
    names = [name for _, name in slots]
    y_of = {}
    for i, name in slots:
        app, cols = models[name]
        height = 30 + row_h * len(cols)
        x = 20 + i * (width + 80)
        y = y_of.get(i, 20)
        y_of[i] = y + height + 30
        tid = d._next('tbl')
        ids[name] = tid
        d.raw(f'<mxCell id="{tid}" value="{_snake(name)}" style="swimlane;fontStyle=1;'
              'childLayout=stackLayout;horizontal=1;startSize=30;horizontalStack=0;'
              'resizeParent=1;resizeLast=0;collapsible=0;html=1;fillColor=#2b5b8a;'
              'fontColor=#ffffff;strokeColor=#2b5b8a;strokeWidth=1.5;fontSize=14;" '
              'vertex="1" parent="1">'
              f'<mxGeometry x="{x}" y="{y}" width="{width}" height="{height}" '
              'as="geometry"/></mxCell>')
        for i, (key, col, _) in enumerate(cols):
            label = f'{key} {col}' if key else col
            d.raw(f'<mxCell id="{tid}r{i}" value="{html.escape(label)}" style="text;'
                  'strokeColor=none;fillColor=none;align=left;verticalAlign=middle;'
                  'spacingLeft=6;html=1;fontSize=13;" vertex="1" parent="' + tid + '">'
                  f'<mxGeometry y="{30 + i * row_h}" width="{width}" height="{row_h}" '
                  'as="geometry"/></mxCell>')
    # Nearly every table names a USER (created_by, cashier, approved_by...);
    # drawn, those lines cross the whole page. The FK columns stay, the lines
    # go, and the note says so.
    for name in names:
        for key, _, target in models[name][1]:
            if key == 'FK' and target in ids and (target != 'User' or name == 'UserGroups'):
                d.edge(ids[target], ids[name],
                       style='edgeStyle=entityRelationEdgeStyle;html=1;endArrow=ERmany;'
                             'startArrow=ERone;endFill=0;startFill=0;strokeWidth=1.5;'
                             'strokeColor=#4a5d78;')
    d.text('Relationship lines to USER (created_by, cashier, approved_by and other '
           'staff columns) are omitted for readability; those columns are marked FK.',
           20, max(y_of.values()) + 10, 900, 20, 'left')
    return d


def export(path, attempts=3):
    """PNG at 2x through the draw.io CLI.

    The CLI sometimes hangs when exports run back to back (it is a
    single-instance Electron app), so each try is capped and retried.
    """
    png = path.with_suffix('.png')
    for attempt in range(1, attempts + 1):
        try:
            subprocess.run([DRAWIO, '-x', '-f', 'png', '-s', '2', '-b', '20', '-o',
                            str(png), str(path)], check=True, capture_output=True,
                           timeout=60)
            return png
        except subprocess.TimeoutExpired:
            if attempt == attempts:
                raise
            print(f'  draw.io hung on {path.name}, retrying ({attempt}/{attempts})')


if __name__ == '__main__':
    builders = [use_case_diagram, cashier_flowchart, stock_manager_flowchart,
                store_manager_flowchart, context_diagram, dfd, erd]
    for build in builders:
        path = build().save()
        print('wrote', path.relative_to(ROOT))
        if '--no-png' not in sys.argv:
            print('  exported', export(path).relative_to(ROOT))
