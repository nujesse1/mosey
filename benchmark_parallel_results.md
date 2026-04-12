# Parallel Benchmark Results
Date: Sat Apr 11 22:08:31 PDT 2026
Workers: 4 | Wall time: 91.5s

| task                 | category   |     time |   turns |    acc |
| ----                 | --------   |     ---- |   ----- |    --- |
| simple_read          | Read       |    12.6s |       2 |    1.0 |
| table_extract        | Read       |    23.6s |       5 |    1.0 |
| wiki_facts           | Read       |    31.2s |       5 |    1.0 |
| book_price           | Read       |    14.9s |       2 |    1.0 |
| form_text_multi      | Forms      |    55.6s |      15 |    1.0 |
| form_dropdown        | Forms      |    42.1s |       8 |    1.0 |
| form_radio_check     | Forms      |    64.2s |      10 |    1.0 |
| login_flow           | Navigation |    59.5s |      15 |    1.0 |
| click_navigate       | Navigation |    24.2s |       4 |    1.0 |
| multi_step           | Navigation |    38.2s |       7 |    1.0 |
| dynamic_load         | Dynamic    |    85.7s |       1 |    1.0 |
| dynamic_controls     | Dynamic    |    87.7s |      21 |    1.0 |
| redirect             | Dynamic    |    38.4s |       7 |    1.0 |
| hn_top3              | Real-World |    15.5s |       2 |    1.0 |
| github_info          | Real-World |    49.7s |       8 |    1.0 |
| hover_tooltip        | Hover      |    39.1s |      10 |    0.5 |

## Summary
| metric | value |
|--------|-------|
| wall time | 91.5s |
| avg accuracy | 0.97 |
| tasks | 16 |
| workers | 4 |
