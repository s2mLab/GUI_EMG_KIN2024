import os
from mcculw import ul
from mcculw.enums import ULRange

cfg_path = r"C:\Users\Public\Documents\Measurement Computing\DAQ\CB.CFG"
print("CB.CFG exists:", os.path.exists(cfg_path), "->", cfg_path)

# Comment/uncomment to test both modes
# ul.ignore_instacal()

from mcculw import ul
from mcculw.enums import ULRange

board = 0
ch = 0
rng = ULRange.BIP5VOLTS

counts = ul.a_in(board, ch, rng)
volts = ul.to_eng_units(board, rng, counts)

print("counts =", counts)
print("volts  =", volts)
