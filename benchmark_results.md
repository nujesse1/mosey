# Weblens vs Browser-Use Benchmark
Date: Sat Apr 11 17:37:11 PDT 2026
Model: claude-opus-4-6 (via Claude Code)


## Task 1: simple_read
**Prompt:** Go to https://example.com and tell me exactly what text is on the page.

### weblens: 11.6s
```
Here's the exact text on the page:

**Heading:** "Example Domain"

**First paragraph:** "This domain is for use in documentation examples without needing permission. Avoid use in operations."

**Second paragraph:** Contains a link labeled "Learn more" pointing to `https://iana.org/domains/example`.
```

### chrome MCP: 13.9s
```
Here's the exact text on https://example.com:

- **Heading:** "Example Domain"
- **Body text:** "This domain is for use in documentation examples without needing permission. Avoid use in operations."
- **Link:** "Learn more" (pointing to https://iana.org/domains/example)

That's the entire page content — just a heading, one sentence of description, and a link.
```


## Task 2: list_extraction
**Prompt:** Go to https://news.ycombinator.com and tell me the titles of the top 3 stories.

### weblens: 31.4s
```
I already have enough from the snapshot. Here are the top 3 stories on Hacker News right now:

1. **Small models also found the vulnerabilities that Mythos found** (aisle.com) — 781 points, 211 comments
2. **Apple Silicon and Virtual Machines: Beating the 2 VM Limit (2023)** (khronokernel.com)
3. **How We Broke Top AI Agent Benchmarks: And What Comes Next** (rdi.berkeley.edu)
```

### chrome MCP: 19.7s
```
Here are the top 3 stories on Hacker News right now:

1. **Small models also found the vulnerabilities that Mythos found** (aisle.com) — 781 points, 211 comments
2. **Apple Silicon and Virtual Machines: Beating the 2 VM Limit (2023)** (khronokernel.com) — 121 points, 63 comments
3. **How We Broke Top AI Agent Benchmarks: And What Comes Next** (rdi.berkeley.edu) — 195 points, 51 comments
```


## Task 3: wiki_lookup
**Prompt:** Go to https://en.wikipedia.org/wiki/Anthropic and tell me when the company was founded and who founded it.

### weblens: 15.7s
```
**Anthropic** was **founded in 2021** by **seven former employees of OpenAI**, including siblings **Daniela Amodei** and **Dario Amodei** (who was OpenAI's Vice President of Research). Other notable co-founders include **Jack Clark** (head of policy) and additional researchers from OpenAI. Dario serves as CEO and Daniela as President.
```

### chrome MCP: 31.1s
```
Here's what I found from the Wikipedia article:

- **Founded:** 2021
- **Founders:** Anthropic was founded by **Dario Amodei** and **Daniela Amodei**, along with five other former employees of OpenAI. Dario had previously served as OpenAI's Vice President of Research, and Daniela is co-founder and President of Anthropic.
```


## Task 4: form_interaction
**Prompt:** Go to https://httpbin.org/forms/post and fill in the customer name field with 'Test User' and the telephone field with '555-1234'. Tell me what fields you see on the form.

### weblens: 17.9s
```
- **Delivery instructions** — empty

**Pizza Size** (radio buttons):
- Small, Medium, Large

**Pizza Toppings** (checkboxes):
- Bacon, Extra Cheese, Onion, Mushroom

**Submit button:**
- "Submit order"
```

### chrome MCP: 32.6s
```
1. **Customer name** (text input) — filled with "Test User"
2. **Telephone** (text input) — filled with "555-1234"
3. **E-mail address** (text input)
4. **Pizza Size** (radio buttons: Small, Medium, Large)
5. **Pizza Toppings** (checkboxes: Bacon, Extra Cheese, Onion, Mushroom)
6. **Preferred delivery time** (time picker with hours, minutes, AM/PM)
7. **Delivery instructions** (multiline text area)
8. **Submit order** (button)

It's a pizza order form!
```


## Task 5: scrape_data
**Prompt:** Go to https://books.toscrape.com, tell me the title and price of the first book listed.

### weblens: 27.2s
```
The first book listed is:

- **Title:** A Light in the Attic
- **Price:** £51.77
```

### chrome MCP: 12.0s
```
The first book listed is:

- **Title:** A Light in the Attic
- **Price:** £51.77
```

