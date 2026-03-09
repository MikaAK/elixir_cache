# Elixir Style Guide

Source: https://github.com/christopheradams/elixir_style_guide

## Formatting

Elixir v1.6+ has a Code Formatter (`mix format`). The formatter should be preferred for all new projects and source code. The rules in this section are applied automatically by the formatter but are provided as reference.

### Whitespace

- Avoid trailing whitespace
- End each file with a newline
- Use Unix-style line endings
- Limit lines to 98 characters (or set `:line_length` in `.formatter.exs`)
- Use spaces around operators, after commas, colons and semicolons. No spaces around matched pairs (brackets, parentheses, etc.)

```elixir
sum = 1 + 2
{a, b} = {2, 3}
[first | rest] = [1, 2, 3]
Enum.map(["one", <<"two">>, "three"], fn num -> IO.puts(num) end)
```

- No spaces after non-word unary operators or around the range operator

```elixir
0 - 1 == -1
^pinned = some_func()
5 in 1..10
```

- Use blank lines between `def`s to break up a function into logical paragraphs
- Don't put a blank line after `defmodule`
- If the function head and `do:` clause are too long to fit on the same line, put `do:` on a new line, indented one level more than the previous line
- When the `do:` clause starts on its own line, treat it as a multiline function by separating it with blank lines

```elixir
# not preferred
def some_function([]), do: :empty
def some_function(_),
  do: :very_long_line_here

# preferred
def some_function([]), do: :empty

def some_function(_),
  do: :very_long_line_here
```

- Add a blank line after a multiline assignment as a visual cue that the assignment is 'over'

```elixir
some_string =
  "Hello"
  |> String.downcase()
  |> String.trim()

another_string <> some_string
```

- If a list, map, or struct spans multiple lines, put each element, as well as the opening and closing brackets, on its own line. Indent each element one level, but not the brackets.

```elixir
# preferred
[
  :first_item,
  :second_item,
  :next_item,
  :final_item
]
```

- When assigning a list, map, or struct, keep the opening bracket on the same line as the assignment

```elixir
list = [
  :first_item,
  :second_item
]
```

- If any `case` or `cond` clause needs more than one line, use multi-line syntax for all clauses, and separate each one with a blank line

```elixir
case arg do
  true ->
    IO.puts("ok")
    :ok

  false ->
    :error
end
```

- Place comments above the line they comment on
- Use one space between the leading `#` and the text

### Indentation

- Indent and align successive `with` clauses. Put the `do:` argument on a new line, aligned with the previous clauses.

```elixir
with {:ok, foo} <- fetch(opts, :foo),
     {:ok, my_var} <- fetch(opts, :my_var),
     do: {:ok, foo, my_var}
```

- If the `with` expression has a `do` block with more than one line, or has an `else` option, use multiline syntax

```elixir
with {:ok, foo} <- fetch(opts, :foo),
     {:ok, my_var} <- fetch(opts, :my_var) do
  {:ok, foo, my_var}
else
  :error ->
    {:error, :bad_arg}
end
```

### Parentheses

- Use parentheses for one-arity functions when using the pipe operator (`|>`)

```elixir
some_string |> String.downcase() |> String.trim()
```

- Never put a space between a function name and the opening parenthesis

```elixir
# not preferred
f (3 + 2)

# preferred
f(3 + 2)
```

- Use parentheses in function calls, especially inside a pipeline

```elixir
# preferred
2 |> rem(3) |> g()
```

- Omit square brackets from keyword lists whenever they are optional

```elixir
some_function(foo, bar, a: "baz", b: "qux")
```

## The Guide

### Expressions

- Run single-line `def`s that match for the same function together, but separate multiline `def`s with a blank line

```elixir
def some_function(nil), do: {:error, "No Value"}
def some_function([]), do: :ok

def some_function([first | rest]) do
  some_function(rest)
end
```

- If you have more than one multiline `def`, do not use single-line `def`s
- Use the pipe operator to chain functions together

```elixir
some_string
|> String.downcase()
|> String.trim()
```

- Avoid using the pipe operator just once

```elixir
# not preferred
some_string |> String.downcase()

# preferred
String.downcase(some_string)
```

- Use bare variables in the first part of a function chain

```elixir
# not preferred
String.trim(some_string) |> String.downcase() |> String.codepoints()

# preferred
some_string |> String.trim() |> String.downcase() |> String.codepoints()
```

- Use parentheses when a `def` has arguments, and omit them when it doesn't

```elixir
def some_function(arg1, arg2) do
  ...
end

def some_function do
  ...
end
```

- Use `do:` for single line `if`/`unless` statements
- Never use `unless` with `else` — rewrite with the positive case first

```elixir
if success do
  IO.puts('success')
else
  IO.puts('failure')
end
```

- Use `true` as the last condition of the `cond` special form when you need a clause that always matches

```elixir
cond do
  1 + 2 == 5 ->
    "Nope"

  true ->
    "OK"
end
```

- Use parentheses for calls to functions with zero arity, so they can be distinguished from variables

```elixir
def my_func do
  do_stuff()
end
```

### Naming

Follows the [Naming Conventions](https://hexdocs.pm/elixir/naming-conventions.html) from the Elixir docs.

- Use `snake_case` for atoms, functions and variables
- Use `CamelCase` for modules (keep acronyms like HTTP, RFC, XML uppercase)
- Functions that return a boolean should be named with a trailing question mark `?`

```elixir
def cool?(var) do
  String.contains?(var, "cool")
end
```

- Boolean checks that can be used in guard clauses should be named with an `is_` prefix

```elixir
defguard is_cool(var) when var == "cool"
```

- Private functions should not have the same name as public functions. The `def name` and `defp do_name` pattern is discouraged — find more descriptive names focusing on the differences.

```elixir
def sum(list), do: sum_total(list, 0)

defp sum_total([], total), do: total
defp sum_total([head | tail], total), do: sum_total(tail, head + total)
```

### Comments

- Write expressive code and try to convey your program's intention through control-flow, structure and naming
- Comments longer than a word are capitalized, and sentences use punctuation. Use one space after periods.
- Limit comment lines to 100 characters

#### Comment Annotations

- Annotations should be written on the line immediately above the relevant code
- The annotation keyword is uppercase, followed by a colon and a space, then a note

```elixir
# TODO: Deprecate in v1.5.
def some_function(arg), do: {:ok, arg}
```

- `TODO` — missing features to add later
- `FIXME` — broken code that needs fixing
- `OPTIMIZE` — slow or inefficient code
- `HACK` — code smells to refactor away
- `REVIEW` — confirm it works as intended

### Modules

- Use one module per file unless the module is only used internally by another module (such as a test)
- Use `snake_case` file names for `CamelCase` module names
- Represent each level of nesting within a module name as a directory

```elixir
# file is called parser/core/xml_parser.ex
defmodule Parser.Core.XMLParser do
end
```

- List module attributes, directives, and macros in this order:
  1. `@moduledoc`
  2. `@behaviour`
  3. `use`
  4. `import`
  5. `require`
  6. `alias`
  7. `@module_attribute`
  8. `defstruct`
  9. `@type`
  10. `@callback`
  11. `@macrocallback`
  12. `@optional_callbacks`
  13. `defmacro`, `defmodule`, `defguard`, `def`, etc.

Add a blank line between each grouping, and sort the terms alphabetically.

- Use `__MODULE__` pseudo variable when a module refers to itself
- Avoid repeating fragments in module names and namespaces

```elixir
# not preferred
defmodule Todo.Todo do ... end

# preferred
defmodule Todo.Item do ... end
```

### Documentation

- Always include a `@moduledoc` attribute right after `defmodule`
- Use `@moduledoc false` if you do not intend on documenting the module
- Separate code after the `@moduledoc` with a blank line
- Use heredocs with markdown for documentation

```elixir
defmodule SomeModule do
  @moduledoc """
  About the module

  ## Examples

      iex> SomeModule.some_function
      :result
  """
end
```

### Typespecs

- Place `@typedoc` and `@type` definitions together, separated by blank lines
- If a union type is too long for one line, put each part on a separate line

```elixir
@type long_union_type ::
        some_type
        | another_type
        | some_other_type
```

- Name the main type for a module `t`

```elixir
defstruct [:name, params: []]

@type t :: %__MODULE__{
        name: String.t() | nil,
        params: Keyword.t()
      }
```

- Place `@spec` right before the function definition, after `@doc`, without a blank line

```elixir
@doc """
Some function description.
"""
@spec some_function(term) :: result
def some_function(some_data) do
  {:ok, some_data}
end
```

### Structs

- Use a list of atoms for struct fields that default to nil, followed by keyword defaults

```elixir
defstruct [:name, :params, active: true]
```

- Omit square brackets when the argument of a `defstruct` is a keyword list

```elixir
defstruct params: [], active: true

# brackets required when mixing atoms and keywords
defstruct [:name, params: [], active: true]
```

- If a struct definition spans multiple lines, put each element on its own line, keeping the elements aligned

### Exceptions

- Make exception names end with a trailing `Error`

```elixir
defmodule BadHTTPCodeError do
  defexception [:message]
end
```

- Use lowercase error messages when raising exceptions, with no trailing punctuation

```elixir
raise ArgumentError, "this is not valid"
```

### Collections

- Always use the special syntax for keyword lists

```elixir
some_value = [a: "baz", b: "qux"]
```

- Use the shorthand key-value syntax for maps when all keys are atoms

```elixir
%{a: 1, b: 2, c: 3}
```

- Use the verbose key-value syntax for maps if any key is not an atom

```elixir
%{:a => 1, :b => 2, "c" => 0}
```

### Strings

- Match strings using the string concatenator rather than binary patterns

```elixir
"my" <> _rest = "my string"
```

### Metaprogramming

- Avoid needless metaprogramming

### Testing

- When writing ExUnit assertions, put the expression being tested to the left of the operator, and the expected result to the right, unless the assertion is a pattern match

```elixir
assert actual_function(1) == true
assert {:ok, expected} = actual_function(3)
```
