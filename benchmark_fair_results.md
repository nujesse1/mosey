# Fair Benchmark: weblens vs Chrome
Date: Sat Apr 11 22:14:19 PDT 2026 | Wall time: 150.8s | Workers: 4

| task                 | category   |  wl_time |  cr_time | wl_turn |  cr_turn | wl_acc | cr_acc |
| ----                 | --------   |  ------- |  ------- | ------- | -------- | ------ | ------ |
| simple_read          | Read       |    13.9s |    68.2s |       2 |        7 |    1.0 |    1.0 |
| table_extract        | Read       |   130.0s |    98.0s |      13 |        8 |    1.0 |    1.0 |
| wiki_facts           | Read       |   115.6s |    67.9s |      15 |        5 |    1.0 |    1.0 |
| book_price           | Read       |   102.1s |    76.2s |       4 |        7 |    1.0 |    0.0 |
| form_text_multi      | Forms      |   118.7s |   135.8s |       8 |       14 |    1.0 |    1.0 |
| form_dropdown        | Forms      |   111.2s |   148.8s |      11 |       12 |    1.0 |    1.0 |
| form_radio_check     | Forms      |    66.9s |    68.5s |       6 |        6 |    0.0 |    0.0 |
| login_flow           | Navigation |   123.3s |   112.8s |      15 |       12 |    0.0 |    0.0 |
| click_navigate       | Navigation |   101.0s |    68.8s |      12 |        6 |    1.0 |    0.0 |
| multi_step           | Navigation |    82.5s |    65.8s |       3 |       10 |    1.0 |    1.0 |
| dynamic_load         | Dynamic    |   137.9s |   118.5s |       1 |        9 |    1.0 |    0.0 |
| dynamic_controls     | Dynamic    |   129.3s |   128.2s |      15 |       23 |    0.0 |    1.0 |
| redirect             | Dynamic    |    99.6s |    64.3s |      11 |        5 |    1.0 |    0.0 |
| hn_top3              | Real-World |    61.4s |    62.0s |       2 |        4 |    1.0 |    1.0 |
| github_info          | Real-World |    95.5s |    19.3s |      10 |        1 |    0.5 |    0.5 |
| hover_tooltip        | Hover      |    43.2s |    18.7s |       4 |        1 |    0.5 |    0.0 |

## Summary
| metric | weblens | chrome | winner |
|--------|---------|--------|--------|
| avg time/task | 95.8s | 82.6s | chrome |
| avg accuracy | 0.75 | 0.53 | weblens |
| wall time | 150.8s | — | — |
