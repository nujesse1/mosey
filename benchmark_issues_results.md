# Weblens Issue Tests
Date: Sat Apr 11 20:24:47 PDT 2026

{
  "stopped": true
}
# Example Domain
# https://example.com/

h1 "Example Domain"
  text: This domain is for use in documentation examples without needing permission. Avoid use in operations.
[e6] link "Learn more" → https://iana.org/domains/example
Daemon warm.

## form_fill_all
**Time: 24.0s**
```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
All four text fields filled successfully. Here's every field on the form:

**Text fields**
| Ref | Field | Filled value |
|-----|-------|-------------|
| e5 | Customer name | `Test User` |
| e8 | Telephone | `555-1234` |
| e11 | E-mail address | `test@test.com` |
| e39 | Preferred delivery time | *(left empty — not requested)* |
| e42 | Delivery instructions | `Leave at door` |

**Radio buttons** (Pizza size — mutually exclusive, none selected)
| Ref | Option |
|-----|--------|
| e16 | Small |
| e19 | Medium |
| e22 | Large |

**Checkboxes** (Toppings — none checked)
| Ref | Option |
|-----|--------|
| e27 | Bacon |
| e30 | Extra Cheese |
| e33 | Onion |
| e36 | Mushroom |

**Button**
| Ref | Label |
|-----|-------|
| e44 | Submit order |

**Total: 14 fields** — 5 textboxes, 3 radio buttons, 4 checkboxes, 1 button.
```

## search_and_navigate
**Time: 19.2s**
```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
The first result is **Playwright (software)** — there's no Wikipedia article titled "Playwright browser automation" (it doesn't exist yet), but the top actual search result listed is `Playwright (software)`.
```

## json_api
**Time: 16.5s**
```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
The first 5 Hacker News top story IDs are:

1. `47732020`
2. `47735704`
3. `47735535`
4. `47733217`
5. `47733971`

Note: `weblens navigate` renders pages in a browser — for raw JSON APIs, `curl` is the better fit since the browser snapshot doesn't capture the response body directly.
```

## form_radio_checkbox
