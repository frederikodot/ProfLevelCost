Changes:
- Checkbox/dropdown/detail changes no longer trigger calculations.
- Tab switching does not calculate; it only shows cached results if available.
- Auctionator DB updates + /plc setprice/clearprice mark results dirty (no auto-calc).
- Only the Calculate button runs the heavy report build for the current view.
