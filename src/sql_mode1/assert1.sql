\qecho '=== tlib public functions: =================================='
SELECT tlib.normalizeterm('  test test0 - TEST, test2/test2,  "test3"  test4.test   ');
SELECT tlib.multimetaphone('paralelepipedo quadrado da Maria'),
       tlib.multimetaphone('paralelepipedo quadrado da Maria', 10, '&');
