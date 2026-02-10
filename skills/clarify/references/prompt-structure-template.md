# Prompt Structure Template

8-section framework for structuring effective prompts. Use only the sections relevant to the input.

## 1. Role & Context
Define who the assistant is, its role, high-level goal, and communication style (tone, personality, formality). Combine identity and style in one block — they're almost always specified together.

## 2. Background Data
Reference material the assistant should use. Key rules:
- **Wrap in XML tags**: `<reference_material>...</reference_material>`, `<document>...</document>`, etc.
- **Place BEFORE instructions** that reference it — long inputs go first, directions follow
- Use descriptive tag names matching the content type (`<api_spec>`, `<style_guide>`, `<error_log>`)

## 3. Task Description & Rules
The explicit behavioural rules and constraints. When restructuring:
- **State the WHY** behind each constraint when inferrable ("Keep under 280 chars — this will be a tweet")
- **Frame positively** — say what TO DO, not what to avoid (see examples in SKILL.md)
- If examples exist (section 4), verify they actually demonstrate these rules — examples override instructions when they conflict

## 4. Examples
Few-shot examples of ideal behaviour. Guidelines from Anthropic's metaprompt:
- Examples strongly shape behaviour — ensure they align with stated rules
- Show the exact output format desired
- Include edge cases, not just happy paths
- Use XML tags to demarcate example structure (`<example>`, `<ideal_output>`)

## 5. Immediate Task
The user's actual question or request — the core of what was extracted from raw input. Place this after context and rules so the model has full information before acting.

## 6. Reasoning Approach
For complex tasks, instruct reasoning inside `<thinking>` tags before producing the final answer. For simple tasks, omit entirely — don't add overhead where it isn't needed.

## 7. Output Format
Exact output structure if specified. Key techniques:
- Use XML format indicator tags (`<analysis>`, `<recommendation>`, `<answer>`)
- Match the prompt's formatting style to desired output — markdown prompts beget markdown output
- Ask for justification/reasoning BEFORE scores or verdicts

## 8. Execution Directive
"Answer immediately without preamble." Prevents the "Sure! I'd be happy to help..." pattern. Replaces deprecated prefilled-response technique (no longer supported in Claude Opus 4.6+).
