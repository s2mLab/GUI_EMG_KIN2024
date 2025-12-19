from mcculw import ul
from mcculw.enums import ULRange

board = 0
ch = 0

v = ul.a_in(board, ch, ULRange.BIP5VOLTS)
print("AI0 =", v, "V")
