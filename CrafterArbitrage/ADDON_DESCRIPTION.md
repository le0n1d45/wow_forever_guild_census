# CurseForge listing text

Copy-paste source for the CurseForge project page. The README is for developers and GitHub; this
is for players. When features change, update this file alongside the README, then paste the new
text into CurseForge (Project > Edit > Description).

How to use it:

1. **Summary field:** paste the single line under "Summary" below (CurseForge limits it to about 250
   characters).
2. **Description field:** paste everything under "Description" below, between the two `---` lines.
3. **Icon:** `assets/crafterarbitrage-icon.png` in the repo root.

## Summary

Scan the Auction House and see which crafts make gold: buy the reagents, craft, sell to a vendor (or on the Auction House). Filter by recipes you know, can learn from a trainer, or all.

## Description

---

# CrafterArbitrage

**Find crafts that turn a profit.**

Open the Auction House, press **Scan**, and CrafterArbitrage lists the crafts that earn more than their
reagents cost, best profit first, with how many to make.

- **Sell to a vendor** (the default, a guaranteed sale) or tick **Sell on the Auction House** to see what pays
  there, after the cut (and the neutral Auction House's higher one).
- **Prices climb as you buy.** Reagents are priced listing by listing, so it stops where the next craft would
  no longer pay. Reagents a vendor sells count at the vendor's price, and a reagent you can craft yourself
  (a bolt of cloth) is crafted when that is cheaper.
- **Pick your recipes:** **Known** (what you can make now), **Learnable** (plus what a trainer of your faction
  teaches at your skill, with the price) or **All** (every recipe, with where to get it: vendor, quest or drop).
- **Hover a row** for the shopping list, the profit, and where the trainer or recipe seller stands.

The Auction House allows one full scan every 15 minutes; CrafterArbitrage also reads a scan another addon
(Auctionator) started.

Type **/carb** to open the window. Other commands: **/carb scan**, **/carb ah**, **/carb vendor**,
**/carb filter known|learnable|all**, **/carb neutral on|off**, **/carb minimap on|off**.

A **minimap button** opens the window (left-click), scans the Auction House (right-click), and can be dragged
around the minimap.

---

**Under vendor price:** the same scan also finds auctions listed for less than a vendor pays for the item. Press **Under vendor price** in the window to see them, best profit first: buy them out and sell them to a vendor.
