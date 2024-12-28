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

    defparsecp :parse_program, program |> post_traverse(:structure_final_output)

    defp structure_final_output(_rest, tokens, context, _line, _offset) do
      {tokens, context}
    end

    @spec parse(binary()) :: {:ok, list()} | {:error, <<_::21032>>, binary()}
    def parse(input) when is_binary(input) do
      case parse_program(input) do
        {:ok, tokens, "", _, _, _} ->
          {:ok, Enum.map(tokens, &process_token/1)}
        {:error, message, rest, _, _, _} ->
          {:error, message, rest}
      end
    end

    defp process_token(tokens) when is_list(tokens) do
      %{
        name: case Enum.find(tokens, fn {t, _} -> t == :name end) do
          {:name, [name]} -> name
          _ -> ""
        end,
        inputs: extract_destinations(tokens),
        outputs: case Enum.find(tokens, fn {t, _} -> t == :source end) do
          {:source, ["IN", "<", ">"]} -> "IN<>"
          _ -> ""
        end,
        resolution: extract_resolution(tokens),
        type: :definition
      }
    end

    defp process_token({:invocation, tokens}) do
      %{
        dest: extract_value(tokens, :dest),
        function: extract_value(tokens, :function),
        arguments: extract_arguments(tokens),
        type: :invocation
      }
    end

    defp process_token(%{type: :definition} = def), do: def

  defparsecp :parse_final, parser

  defp structure_output(_rest, tokens, context, _line, _offset) do
    # Find source directly
    outputs = case Enum.find(tokens, fn
      {:source, _} -> true
      _ -> false
    end) do
      {:source, ["IN", "<", ">"]} -> "IN<>"
      _ -> ""
    end

    result = %{
      name: extract_value(tokens, :name),
      inputs: extract_destinations(tokens),
      outputs: outputs,
      resolution: extract_resolution(tokens),
      type: :definition
    }
    {[result], context}
  end

  defp extract_resolution(tokens) when is_list(tokens) do
    case Enum.find(tokens, fn
      {:resolution, _} -> true
      _ -> false
    end) do
      {:resolution, resolution_tokens} ->
        resolution_tokens
        |> Enum.filter(fn
          {:mapping, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:mapping, [{:pattern, [p]}, {:value, [v]}]} ->
          {p, v}
        end)
      _ -> []
    end
  end

  defp extract_resolution(%{resolution: res}), do: res
  defp extract_resolution(_), do: []

  defp extract_arguments(tokens) do
    tokens
    |> Enum.filter(fn
      {:argument, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:argument, value} -> List.to_string(value) end)
  end

  defp extract_destinations(tokens) when is_list(tokens) do
    tokens
    |> Enum.filter(fn
      {:destination, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:destination, [_, value]} -> "$" <> value end)
  end

  defp extract_destinations(%{inputs: inputs}) when is_list(inputs) do
    inputs
  end

  defp extract_destinations(_), do: []

  defp extract_value(tokens, tag) do
    IO.inspect({tokens, tag}, label: "extract_value detailed")
    case tokens do
      list when is_list(list) ->
        found = Enum.find(list, fn
          {^tag, _} -> true
          _ -> false
        end)
        IO.inspect(found, label: "found token")
        case found do
          {:source, values} ->
            IO.inspect(values, label: "source values")
            case values do
              ["IN", "<", ">"] -> "IN<>"
              ["IN"] -> "IN<>"
              _ -> ""
            end
          {_, [value | _]} -> value
          {_, value} when is_binary(value) -> value
          _ -> ""
        end
      map when is_map(map) ->
        Map.get(map, tag, "")
      _ -> ""
    end
  end
end
