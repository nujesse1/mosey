# weblens Rerun vs Chrome (preserved)
Date: Sat Apr 11 21:56:01 PDT 2026
weblens: new build with hover + img fixes

## Results

| task                 | category   |  wl_time |  cr_time | wl_acc | cr_acc | wl_turns | cr_turns |
| ----                 | --------   |  ------- |  ------- | ------ | ------ | -------- | -------- |
| simple_read          | Read       |     4.7s |    10.2s |   1.0 |   1.0 |       2 |        2 |
| table_extract        | Read       |    16.7s |    58.0s |   1.0 |   1.0 |       6 |        6 |
| wiki_facts           | Read       |    10.4s |     9.1s |   1.0 |   1.0 |       4 |        2 |
| book_price           | Read       |     5.5s |     8.0s |   1.0 |   1.0 |       2 |        2 |
| form_text_multi      | Forms      |     9.5s |    12.4s |   1.0 |   1.0 |       3 |        3 |
| form_dropdown        | Forms      |    15.5s |     —s |   1.0 |   — |       7 |      — |
| form_radio_check     | Forms      |     8.8s |     —s |   1.0 |   — |       3 |      — |
| login_flow           | Navigation |    11.3s |     —s |   1.0 |   — |       4 |      — |
| click_navigate       | Navigation |     6.5s |     —s |   1.0 |   — |       3 |      — |
| multi_step           | Navigation |     7.1s |     —s |   1.0 |   — |       3 |      — |
| dynamic_load         | Dynamic    |    12.4s |     —s |   1.0 |   — |       3 |      — |
| dynamic_controls     | Dynamic    |    21.7s |     —s |   1.0 |   — |       8 |      — |
| redirect             | Dynamic    |     7.2s |     —s |   1.0 |   — |       3 |      — |
| hn_top3              | Real-World |     5.1s |     —s |   1.0 |   — |       2 |      — |
| github_info          | Real-World |     7.8s |     —s |   1.0 |   — |       2 |      — |
| hover_tooltip        | Hover      |    11.5s |     —s |   0.5 |   — |       5 |      — |

## Summary (weblens new build)

| metric | value |
|--------|-------|
| avg time | 10.1s |
| avg accuracy | 0.97 |
| tasks | 16 |
