@@ This test shows a difference between m2 and m4.
@@ m4's index function is zero-based, and an m4 document says:
@@   (e.g., index(the quick brown fox jumped, fox) returns 16).
@@ m2 follows the Awk convention of numbering characters in a string from 1.
@@ Thus, the index printed for this file is 17.
@define m4text	the quick brown fox jumped
@index m4text fox@
