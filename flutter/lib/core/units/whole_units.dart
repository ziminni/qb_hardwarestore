/// Units sold in indivisible counts (Phase 6 decision 17).
///
/// ONE home for the list. The quantity dialog refuses a fractional count for these
/// units and the till's scan path adds one straight to the cart without asking, so
/// two copies of the list would let a scan add "1 box" while the dialog still
/// insisted on whole numbers for `BOX`.
///
/// Compared lower-cased: the server's unit codes are upper-case (`PC`, `BOX`).
const wholeUnitCodes = {'pc', 'piece', 'bag', 'box', 'sheet', 'roll', 'pack'};

/// True when [code] names a unit that is only sold in whole counts.
bool isWholeUnit(String code) => wholeUnitCodes.contains(code.trim().toLowerCase());
