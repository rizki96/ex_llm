defmodule ExUnitDebugTest do
  use ExUnit.Case

  @moduletag :integration
  @tag :special

  setup context do
    IO.puts("\n=== ExUnit Context Debug ===")
    IO.puts("Context keys: #{inspect(Map.keys(context))}")
    IO.puts("Module: #{inspect(context.module)}")
    IO.puts("Test: #{inspect(context.test)}")
    IO.puts("Tags: #{inspect(Map.get(context, :tags, []))}")

    # Check process dictionary
    IO.puts("\nProcess dictionary (ExUnit related):")

    Process.get()
    |> Enum.filter(fn {k, _v} ->
      case k do
        atom when is_atom(atom) -> String.contains?(to_string(atom), "ex_unit")
        _ -> false
      end
    end)
    |> Enum.each(fn {k, v} -> IO.puts("  #{inspect(k)}: #{inspect(v)}") end)

    {:ok, context}
  end

  test "check context", context do
    IO.puts("\nInside test - context: #{inspect(Map.keys(context))}")
    assert context.module == __MODULE__
  end
end
