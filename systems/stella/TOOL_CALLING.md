# Stella Tool Calling Guide

## Overview

Stella's Qwen3-Coder-30B-A3B-Instruct model supports tool/function calling using the **Hermes format** (not OpenAI format).

- **Parser**: `hermes` (specified with `--tool-call-parser hermes`)
- **Auto-choice**: Enabled with `--enable-auto-tool-choice`  
- **Format**: XML-style tags (not JSON)

---

## Tool Calling Format

### Request Format (OpenAI-Compatible)

You can use standard OpenAI tool calling format in requests:

```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "What is the weather in Paris?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather for a location",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {
                "type": "string",
                "description": "City name"
              },
              "unit": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"],
                "description": "Temperature unit"
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto"
  }'
```

### Response Format (Hermes XML)

The model returns tool calls in **Hermes XML format**:

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1769384360,
  "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "<tool_call>\n<function=get_weather>\n<parameter=location>\nParis\n</parameter>\n</function>\n</tool_call>",
        "tool_calls": []
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 281,
    "total_tokens": 303,
    "completion_tokens": 22
  }
}
```

**Important**: The `tool_calls` array is **empty** because Hermes format doesn't convert to OpenAI's JSON structure. The tool call is in the `content` field as XML.

---

## Parsing Tool Calls

### Hermes XML Format

Tool calls are returned in this XML-style format:

```xml
<tool_call>
<function=FUNCTION_NAME>
<parameter=PARAM_NAME>
PARAM_VALUE
</parameter>
<parameter=ANOTHER_PARAM>
ANOTHER_VALUE
</parameter>
</function>
</tool_call>
```

### Example 1: Single Parameter

**Request**: "What is the weather in Paris?"

**Response**:
```xml
<tool_call>
<function=get_weather>
<parameter=location>
Paris
</parameter>
</function>
</tool_call>
```

### Example 2: Multiple Parameters

**Request**: "Get weather in Tokyo in Celsius"

**Response**:
```xml
<tool_call>
<function=get_weather>
<parameter=location>
Tokyo
</parameter>
<parameter=unit>
celsius
</parameter>
</function>
</tool_call>
```

### Example 3: Multiple Tool Calls

**Request**: "Get weather in both London and New York"

**Response**:
```xml
<tool_call>
<function=get_weather>
<parameter=location>
London
</parameter>
</function>
</tool_call>

<tool_call>
<function=get_weather>
<parameter=location>
New York
</parameter>
</function>
</tool_call>
```

---

## Python Parsing Example

```python
import re
import json

def parse_hermes_tool_call(content: str) -> list[dict]:
    """Parse Hermes XML tool calls into structured format."""
    tool_calls = []
    
    # Find all tool_call blocks
    pattern = r'<tool_call>(.*?)</tool_call>'
    matches = re.findall(pattern, content, re.DOTALL)
    
    for match in matches:
        # Extract function name
        func_match = re.search(r'<function=([^>]+)>', match)
        if not func_match:
            continue
        function_name = func_match.group(1)
        
        # Extract parameters
        params = {}
        param_pattern = r'<parameter=([^>]+)>\s*(.*?)\s*</parameter>'
        param_matches = re.findall(param_pattern, match, re.DOTALL)
        
        for param_name, param_value in param_matches:
            params[param_name] = param_value.strip()
        
        tool_calls.append({
            "function": {
                "name": function_name,
                "arguments": json.dumps(params)
            }
        })
    
    return tool_calls

# Usage
response = {
    "choices": [{
        "message": {
            "content": "<tool_call>\\n<function=get_weather>\\n<parameter=location>\\nParis\\n</parameter>\\n</function>\\n</tool_call>"
        }
    }]
}

content = response["choices"][0]["message"]["content"]
tool_calls = parse_hermes_tool_call(content)

print(json.dumps(tool_calls, indent=2))
# Output:
# [
#   {
#     "function": {
#       "name": "get_weather",
#       "arguments": "{\"location\": \"Paris\"}"
#     }
#   }
# ]
```

---

## Tool Choice Options

The `tool_choice` parameter controls when tools are invoked:

| Value | Behavior |
|-------|----------|
| `"auto"` | Model decides whether to call tools (default) |
| `"none"` | Model never calls tools, always responds directly |
| `{"type": "function", "function": {"name": "FUNC_NAME"}}` | Force specific tool |

### Example: Force Tool Use

```json
{
  "tool_choice": {
    "type": "function",
    "function": {"name": "get_weather"}
  }
}
```

---

## Complete Working Example

```python
import requests
import re
import json

def call_with_tools(prompt: str, tools: list[dict]) -> dict:
    """Call Stella API with tool support."""
    response = requests.post(
        "http://stella.home.arpa:8000/v1/chat/completions",
        headers={"Content-Type": "application/json"},
        json={
            "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
            "messages": [{"role": "user", "content": prompt}],
            "tools": tools,
            "tool_choice": "auto"
        }
    )
    return response.json()

def parse_tool_calls(content: str) -> list[dict]:
    """Parse Hermes format tool calls."""
    tool_calls = []
    pattern = r'<tool_call>(.*?)</tool_call>'
    matches = re.findall(pattern, content, re.DOTALL)
    
    for match in matches:
        func_match = re.search(r'<function=([^>]+)>', match)
        if not func_match:
            continue
        
        function_name = func_match.group(1)
        params = {}
        
        param_pattern = r'<parameter=([^>]+)>\s*(.*?)\s*</parameter>'
        for param_name, param_value in re.findall(param_pattern, match, re.DOTALL):
            params[param_name] = param_value.strip()
        
        tool_calls.append({
            "function": function_name,
            "arguments": params
        })
    
    return tool_calls

# Define available tools
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get current weather for a location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {"type": "string", "description": "City name"},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
                },
                "required": ["location"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_database",
            "description": "Search database for information",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"}
                },
                "required": ["query"]
            }
        }
    }
]

# Make request
result = call_with_tools(
    "What's the weather in Paris and Tokyo in Celsius?",
    tools
)

# Parse response
content = result["choices"][0]["message"]["content"]
tool_calls = parse_tool_calls(content)

print("Tool calls:")
for call in tool_calls:
    print(f"  Function: {call['function']}")
    print(f"  Arguments: {call['arguments']}")
```

---

## Comparison: Hermes vs OpenAI Format

| Aspect | Hermes (Stella) | OpenAI (Pegasus) |
|--------|-----------------|------------------|
| **Request** | OpenAI-compatible | OpenAI format |
| **Response** | XML in `content` | JSON in `tool_calls` |
| **Parser Flag** | `--tool-call-parser hermes` | `--tool-call-parser openai` |
| **Parsing** | Regex/XML parsing | Direct JSON access |
| **tool_calls array** | Empty | Populated |

---

## Tips & Best Practices

### 1. Clear Tool Descriptions

Provide detailed descriptions to help the model choose correctly:

```json
{
  "function": {
    "name": "get_weather",
    "description": "Get current weather conditions including temperature, humidity, and conditions for a specific city or location. Returns real-time weather data."
  }
}
```

### 2. Handle Missing Tool Calls

Not all responses will have tool calls:

```python
if "<tool_call>" in content:
    tool_calls = parse_tool_calls(content)
    # Execute tools
else:
    # Direct text response
    print(content)
```

### 3. Error Handling

```python
try:
    tool_calls = parse_tool_calls(content)
except Exception as e:
    print(f"Failed to parse tool calls: {e}")
    print(f"Raw content: {content}")
```

### 4. Validation

Always validate parsed parameters before executing:

```python
def validate_and_execute(tool_call: dict) -> dict:
    func_name = tool_call["function"]
    args = tool_call["arguments"]
    
    # Validate required parameters
    if func_name == "get_weather":
        if "location" not in args:
            raise ValueError("Missing required parameter: location")
        
        # Execute function
        return get_weather(**args)
```

---

## Troubleshooting

### Tool Calls Not Working

1. **Check parser is enabled**:
   ```bash
   docker logs qwen-coder | grep "tool_call_parser"
   # Should show: 'tool_call_parser': 'hermes'
   ```

2. **Verify tool definitions**: Ensure `tools` array is properly formatted

3. **Check response**: Look in `content` field, not `tool_calls` array

### Malformed XML

If the model returns incomplete XML:

1. Increase `max_tokens` in request
2. Check if model was interrupted mid-response
3. Try simpler tool descriptions

### Model Not Calling Tools

1. Make descriptions more explicit about when to use each tool
2. Try `tool_choice: required` to force tool use
3. Rephrase the user query to be more action-oriented

---

## References

- **vLLM Tool Calling Docs**: https://docs.vllm.ai/en/latest/features/tool_calling.html
- **Hermes Function Calling**: https://github.com/NousResearch/Hermes-Function-Calling
- **Qwen Model Card**: https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct

---

**Last Updated**: 2026-01-25  
**Model**: Qwen/Qwen3-Coder-30B-A3B-Instruct  
**Parser**: Hermes
