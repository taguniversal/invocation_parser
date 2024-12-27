defmodule InvocationParserTest do
  use ExUnit.Case
  doctest InvocationParser

  test "greets the world" do
    assert InvocationParser.hello() == :world
  end
end
