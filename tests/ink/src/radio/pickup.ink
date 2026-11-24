VAR fare = 0
INCLUDE parts/till.ink
-> pickup
=== pickup ===
Meter? # id:pickup
+ [Tip]
  ~ fare = 1
  -> till
+ [Skip] -> till
