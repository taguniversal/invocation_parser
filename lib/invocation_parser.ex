defmodule InvocationParser do
  import NimbleParsec

  name = ascii_string([?a..?z, ?A..?Z], min: 1)

  single_dest =
    string("$")
    |> concat(name)
    |> tag(:destination)

  destination_list =
    single_dest
    |> repeat(
      ignore(string(","))
      |> concat(single_dest)
    )

  source =
    name
    |> string("<")
    |> string(">")
    |> tag(:source)

  pattern = ascii_string([?0, ?1], min: 1) |> tag(:pattern)
  value = ascii_string([?0, ?1], 1) |> tag(:value)

  mapping =
    pattern
    |> ignore(string(":"))
    |> concat(value)
    |> tag(:mapping)

  mappings =
    mapping
    |> repeat(
      ignore(string(" "))
      |> concat(mapping)
    )

  resolution_inputs =
    single_dest
    |> repeat(single_dest)
    |> tag(:resolution_inputs)

  resolution =
    string("[")
    |> concat(resolution_inputs)
    |> string("]")
    |> ignore(string(" "))
    |> concat(mappings)
    |> tag(:resolution)

  argument =
    choice([
      ascii_string([?0, ?1], 1),
      name
    ])
    |> tag(:argument)

  arg_list =
    argument
    |> repeat(
      ignore(string(","))
      |> concat(argument)
    )

  invocation =
    name
    |> tag(:dest)
    |> string("<")
    |> concat(name |> tag(:function))
    |> string("(")
    |> concat(arg_list)
    |> string(")")
    |> string(">")
    |> tag(:invocation)

    definition_parser =
      name
      |> tag(:name)
      |> string("[")
      |> string("(")
      |> concat(destination_list)
      |> string(")")
      |> string("(")
      |> concat(source)
      |> string(")")
      |> ignore(string(" "))
      |> concat(resolution)
      |> string("]")
      |> post_traverse(:structure_output)

    parser =
      choice([
        definition_parser,
        invocation
      ])

    program =
      choice([
        definition_parser,
        invocation
      ])
      |> repeat(
        ignore(string("\n"))
        |> choice([
          definition_parser,
          invocation
        ])
      )

    defparsecp :parse_program, program

    def parse(input) when is_binary(input) do
      case parse_program(input) do
        {:ok, tokens, "", _, _, _} ->
          {:ok, Enum.map(tokens, &process_token/1)}
        {:error, message, rest, _, _, _} ->
          {:error, message, rest}
      end
    end

    defp process_token({:invocation, tokens}) do
      %{
        dest: extract_value(tokens, :dest),
        function: extract_value(tokens, :function),
        arguments: extract_arguments(tokens),
        type: :invocation
      }
    end

    defp process_token(definition) do
      %{
        name: extract_value(definition, :name),
        inputs: extract_destinations(definition),
        outputs: extract_value(definition, :source),
        resolution: extract_resolution(definition),
        type: :definition
      }
    end




  defparsecp :parse_final, parser



  defp structure_output(_rest, tokens, context, _line, _offset) do
    result = %{
      name: extract_value(tokens, :name),
      inputs: extract_destinations(tokens),
      outputs: extract_value(tokens, :source),
      resolution: extract_resolution(tokens),
      type: :definition
    }
    {[result], context}
  end

  defp extract_resolution(tokens) do
    case Enum.find(tokens, fn
      {:resolution, _} -> true
      _ -> false
    end) do
      {:resolution, resolution_tokens} ->
        mappings = for {:mapping, [{:pattern, p}, {:value, v}]} <- resolution_tokens do
          {List.to_string(p), List.to_string(v)}
        end
        mappings
      _ -> []
    end
  end

  defp extract_arguments(tokens) do
    tokens
    |> Enum.filter(fn
      {:argument, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:argument, value} -> List.to_string(value) end)
  end

  defp extract_destinations(tokens) do
    tokens
    |> Enum.filter(fn
      {:destination, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:destination, value} -> List.to_string(value) end)
  end

  defp extract_value(tokens, tag) do
    case Enum.find(tokens, fn {t, _} -> t == tag end) do
      {_, [value]} when is_binary(value) -> value
      {_, value} when is_binary(value) -> value
      {_, value} when is_list(value) -> List.to_string(value)
      _ -> ""
    end
  end
end
