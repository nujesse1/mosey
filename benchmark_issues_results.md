# Weblens Issue Tests
Date: Sat Apr 11 20:30:53 PDT 2026

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
**Time: 17.9s**
```
All four text fields filled. Here's every field on the form:

**Text inputs**
| Field | Type | Value filled |
|---|---|---|
| Customer name | textbox | `Test User` |
| Telephone | textbox | `555-1234` |
| E-mail address | textbox | `test@test.com` |
| Preferred delivery time | textbox | *(left blank — not in your list)* |
| Delivery instructions | textbox | `Leave at door` |

**Radio buttons** (pizza size — mutually exclusive, none pre-selected)
- Small
- Medium
- Large

**Checkboxes** (toppings — none pre-selected)
- Bacon
- Extra Cheese
- Onion
- Mushroom

**Button**
- Submit order

That's 14 total form controls: 5 textboxes, 3 radio buttons, 4 checkboxes, and 1 submit button.
```

## search_and_navigate
**Time: 14.5s**
```
There's no Wikipedia article with the exact title "Playwright browser automation" — the page doesn't exist. However, the first actual search result is:

**Playwright (software)**

That's the top match, linking to `/wiki/Playwright_(software)`.
```

## json_api
**Time: 13.2s**
```
The first 5 item IDs are:

1. `47735704`
2. `47735535`
3. `47732020`
4. `47733217`
5. `47733971`
```

## form_radio_checkbox
**Time: 18.1s**
```
All three selections confirmed from the final snapshot:

- **Pizza size:** `Large` [checked]
- **Toppings:** `Bacon` [checked], `Extra Cheese` [checked]
```

{
  "stopped": true
}
Done.
