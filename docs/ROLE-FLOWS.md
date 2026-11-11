# Role flows — BuildPro POS / Inventory

How each person uses the system, written for the manuscript and the defense. Menus are the real sidebar labels. Phase 4 additions (discount, split and cheque payments, area switcher) are marked **(Phase 4)**; Phase 5 additions are listed at the end.

## Who does what

| Role | Area | Daily job |
| --- | --- | --- |
| Cashier | Point of sale | Sells at the counter, releases CPMS project materials, takes utang payments, handles returns, opens and closes the shift |
| Stock Manager | Inventory | Keeps the catalogue, orders from suppliers, receives deliveries, adjusts stock, answers low-stock alerts |
| Store Manager | Sales | Owns selling beyond the counter (quotations, sales orders), customers and receivables, accepts or declines CPMS project requests, reports, staff. **This is the sales role.** |
| System Administrator | Admin | Users and roles, store settings, audit logs, every report, every area |
| CPMS Service | none (machine) | The CPMS system pushes approved project requests and reads back status and payables |

One person can hold several roles, for example Cashier + Store Manager in a small store. **(Phase 4)** After login they pick an area and can switch from the header at any time.

## Login and areas

```mermaid
flowchart LR
  L[Login] --> R{How many roles?}
  R -- one --> A[Open that role's area]
  R -- several --> P["Pick an area (Phase 4)"]
  P --> A
  A --> S["Header: Switch area (Phase 4)"]
  S --> A
  A --> O[Log out]
```

Typing another role's address sends the user back to their own area; the server refuses the data anyway.

## Cashier

```mermaid
flowchart TD
  S[Open shift: count opening cash] --> T[New transaction]
  T --> F[Scan or search product, choose unit: piece, bag, kg]
  F --> C[Cart: whole units only for pieces and bags]
  C --> H{Customer waiting?}
  H -- step away --> HD[Held transactions: resume or void later]
  H -- pay now --> D["Discount with reason (Phase 4), over the cap: manager approves"]
  D --> PAY["Payment: cash, card, GCash, cheque; several at once (Phase 4)"]
  PAY --> U{Fully paid?}
  U -- no, named customer --> UT[Rest becomes utang]
  U -- yes --> RC[Receipt with Vatable sales and VAT]
  UT --> RC
  T -.-> REL[Release materials: scan CPMS token, release what is on the shelf]
  T -.-> RP[Record payment: customer pays utang]
  T -.-> RT[Returns: refund what was actually paid]
  RC --> X[Close shift: count cash, see the difference]
```

Menu: New transaction · Transaction history · Release materials · Record payment · Held transactions · Shifts · Returns.

## Stock Manager

```mermaid
flowchart TD
  P[Products: add product, how it is sold: base unit and packages] --> PO[Purchases: purchase order to a supplier]
  PO --> RV[Receiving: count what arrived, record delivery receipt]
  RV --> ST[Stock rises by batch, oldest sold first]
  ST --> LS{Below reorder level?}
  LS -- yes --> AL[Low stock alert: dashboard, bell, Low stock page]
  AL --> PO
  ST --> ADJ[Stock adjustments: damage, count corrections, with reason]
  P --> BL["Barcode list: print or download all codes (Phase 4)"]
  P --> LB[Print 50 x 30 mm labels per unit]
```

Stock only enters through a purchase order and Receiving; Add product never invents opening stock. The reorder level is set per product in the product form.

Menu: Dashboard · Products · Categories · Stock · Stock adjustments · Low stock · Purchases · Suppliers · Receiving · Sales · Returns · Reports · Settings.

## Store Manager (sales)

```mermaid
flowchart TD
  Q[Quotations: price a job for a customer] --> SO[Sales orders: customer confirms]
  SO --> CU[Customers: contractors and firms, credit limit]
  CU --> RCV[Receivables: utang per customer and per project]
  RCV --> CH["Cheques: clear or bounce pending cheques (Phase 4)"]
  PR[Project requests from CPMS] --> DEC{Can the store serve it?}
  DEC -- yes --> ACC[Accept, mark any line Not available with reason]
  DEC -- no --> DCL[Decline with reason]
  ACC --> CASH[Cashier releases on token scan]
  CASH --> RCV
  RPT[Reports: sales, discounts, VAT, returns] --> ST[Staff]
```

Menu: Dashboard · Transactions · Quotations · Sales orders · Receivables (Utang and Cheques tabs) · Returns & refunds · Reports · Staff · Project requests. ("Selling", "Customers", "Insights" and "Projects" are section headings, not pages.)

## System Administrator

```mermaid
flowchart LR
  U[User management: create, deactivate, assign one or more roles] --> SET["Settings: VAT on or off, VAT rate, discount cap (Phase 4)"]
  SET --> AUD[Audit logs: who changed what]
  AUD --> MON[Inventory and Sales & POS monitoring, Reports]
  MON --> PRQ[Project requests]
```

Guards: the last Admin cannot be removed; a Store Manager cannot grant Admin.

## CPMS (other system)

```mermaid
sequenceDiagram
  participant C as CPMS
  participant P as POS
  participant M as Store Manager
  participant K as Cashier
  C->>P: Push approved request (project, items, token)
  P-->>C: WAITING
  M->>P: Accept or decline
  K->>P: Scan token, release what is on the shelf
  C->>P: Read status, released and owed amounts
  C->>P: Close the remainder (optional)
```

## Low stock warning

Each product has a reorder level. When stock falls to it, the system raises a Low stock (or Out of stock) alert: shown on the Stock Manager dashboard restock queue, in the bell notifications and on the Low stock page, where it is resolved after reordering.

## Phase 5 additions (planned)

- Stock Manager orders by package ("10 bags at ₱250 per bag"); stock enters in kilograms.
- Store Manager sees supplier bills created at Receiving, pays them (cash, cheque, bank) and watches overdue balances.
- Cashier or Store Manager marks a sale or sales order for delivery with a fee; the Deliveries page moves it Scheduled → Out for delivery → Delivered or Failed.
- Products say where they are stored (Store or Bodega); the receipt and delivery slip say where to pick them up.
