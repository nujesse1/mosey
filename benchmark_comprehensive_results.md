# Comprehensive Benchmark: weblens vs Chrome MCP
Date: Sat Apr 11 20:37:11 PDT 2026
Model: claude-sonnet-4-6 (claude --dangerously-skip-permissions)

Daemon warm.

## Results

| task                 | category   |  wl_time |  cr_time | wl_cost | cr_cost | wl_turns | cr_turns | wl_in_tok | cr_in_tok | wl_out_tok | cr_out_tok |   wl_acc |
| cr_acc               |            |          |          |         |        |        |          |          |          |          |          |          |
| ----                 | --------   |  ------- |  ------- | ------- | ------ | -------- | -------- | --------- | --------- | ---------- | ---------- |   ------ |
| ------               |            |          |          |         |        |        |          |          |          |          |          |          |
| simple_read          | Read       |     5.3s |    10.2s |      $0 |     $0 |      2 |        2 |        4 |        4 |      190 |      336 |      1.0 |
| 1.0                  |            |          |          |         |        |        |          |          |          |          |          |          |
| table_extract        | Read       |    23.2s |    58.0s |      $0 |     $0 |      8 |        6 |       12 |       10 |      715 |     1938 |      1.0 |
| 1.0                  |            |          |          |         |        |        |          |          |          |          |          |          |
| wiki_facts           | Read       |     6.6s |     9.1s |      $0 |     $0 |      2 |        2 |        4 |        4 |      217 |      330 |      1.0 |
| 1.0                  |            |          |          |         |        |        |          |          |          |          |          |          |
| book_price           | Read       |     6.6s |     8.0s |      $0 |     $0 |      2 |        2 |        4 |        4 |      172 |      223 |      1.0 |
| 1.0                  |            |          |          |         |        |        |          |          |          |          |          |          |
| form_text_multi      | Forms      |    12.9s |    12.4s |      $0 |     $0 |      4 |        3 |        6 |        5 |      482 |      523 |      1.0 |
| 1.0                  |            |          |          |         |        |        |          |          |          |          |          |          |
