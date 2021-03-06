defmodule Ravix.Ecto.Parser.ConditionalTokens do
  alias Ravix.RQL.Tokens.{Condition, And, Or, Not, Update}
  alias Ravix.Ecto.Parser.Shared

  @binary_ops [
    >: &Condition.greater_than/2,
    >=: &Condition.greater_than_or_equal_to/2,
    <: &Condition.lower_than/2,
    <=: &Condition.lower_than_or_equal_to/2,
    ==: &Condition.equal_to/2,
    !=: &Condition.not_equal_to/2,
    in: &Condition.in?/2,
    nin: &Condition.not_in/2,
    ne: &Condition.not_equal_to/2
  ]

  @bool_ops [
    and: &And.condition/1,
    or: &Or.condition/1,
    not: &Not.condition/1
  ]

  @update_ops [
    set: &Update.set/3,
    inc: &Update.inc/3,
    dec: &Update.dec/3
  ]

  Enum.map(@update_ops, fn {op, update_function} ->
    def update_op!(unquote(op), _query), do: unquote(update_function)
  end)

  def update_op!(_, query), do: Shared.error(query, "update clause")

  defmacro ecto_binary_tokens(), do: Keyword.keys(@binary_ops)

  defmacro ecto_boolean_tokens(), do: Keyword.keys(@bool_ops)

  Enum.map(@binary_ops, fn {op, ravix_condition} ->
    def binary_op(unquote(op)), do: unquote(ravix_condition)
  end)

  Enum.map(@bool_ops, fn {op, ravix_boolean_op} ->
    def bool_op(unquote(op)), do: unquote(ravix_boolean_op)
  end)
end
