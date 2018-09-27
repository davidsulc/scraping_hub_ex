defmodule SHEx.Endpoints.Storage.Items.QueryParams do
  @moduledoc false

  alias SHEx.Endpoints.{Helpers, Storage}

  defstruct [
    :error,
    :item_index,
    :field_name,
    :pagination,
    :nodata,
    :meta,
    format: :json,
    csv_params: []
  ]

  def from_keywords(params) when is_list(params) do
    __MODULE__
    |> struct(params)
    |> configure_format()
    |> validate_item_index()
    |> validate_field_name()
    |> validate_format()
    |> validate_meta()
    |> validate_nodata()
  end

  defp configure_format(params) do
    params |> process_csv_format()
  end

  defp process_csv_format(%{format: format} = params) when is_list(format) do
    if Keyword.keyword?(format) do
      params |> set_csv_attributes()
    else
      error = {:invalid_param, {:format, "unexpected list value: #{inspect(format)}"}}
      %{params | error: error}
    end
  end

  defp process_csv_format(params), do: params

  defp set_csv_attributes(%{format: format} = params) do
    # we're determining the csv format this way so that a typo like
    # format: [csv: [fields: ["auction", "id"]], sep: ","]
    # instead of
    # format: [csv: [fields: ["auction", "id"], sep: ","]]
		# gets a better error message:
    # {:invalid_param,
    #    {:format,
    #        "multiple values provided: [csv: [fields: [\"auction\", \"id\"]], sep: \",\"]"}}
		# instead of
		# {:invalid_param,
    #    {:format,
    #        "expected format '[csv: [fields: [\"auction\", \"id\"]], sep: \",\"]' to be one of:
    #         [:json, :jl, :xml, :csv, :text]"}}
    case Keyword.get(format, :csv) do
      nil -> params
      csv_params ->
        if length(format) == 1 do
          %{params | format: :csv, csv_params: csv_params}
        else
          error = {:invalid_param, {:format, "multiple values provided: #{inspect(format)}"}}
          %{params | error: error}
        end
    end
  end

  defp validate_item_index(%{item_index: index} = params) when is_integer(index), do: params

  defp validate_item_index(%{item_index: index} = params) when is_binary(index) do
    if String.match?(index, ~r/^\d+$/) do
      params
    else
      error = {:invalid_param, {:item_index, "expected an integer (possibly represented as a string)"}}
      %{params | error: error}
    end
  end

  defp validate_item_index(params) do
    error = {:invalid_param, {:item_index, "expected an integer (possibly represented as a string)"}}
    %{params | error: error}
  end

  defp validate_field_name(%{field_name: nil} = params), do: params
  defp validate_field_name(%{field_name: name} = params) when is_binary(name), do: params
  defp validate_field_name(params) do
    error = {:invalid_param, {:field_name, "expected a string"}}
    %{params | error: error}
  end

  defp validate_format(%{error: error} = params) when error != nil, do: params

  defp validate_format(%{format: :csv} = params) do
    params
    |> validate_csv_params()
    |> check_fields_param_provided()
  end

  defp validate_format(%{format: format} = params) do
    case Storage.validate_format(format) do
      :ok -> params
      error -> %{params | error: error}
    end
  end

  defp validate_csv_params(%{csv_params: csv} = params) do
    case Helpers.validate_params(csv, Storage.csv_params()) do
      :ok ->
        params
      {:invalid_param, error} ->
        error = {:invalid_param, {:csv_param, error}}
        %{params | error: error}
    end
  end

  defp check_fields_param_provided(%{csv_params: csv} = params) do
    if Keyword.has_key?(csv, :fields) do
      params
    else
      error = {:invalid_param, {:csv_param, "required attribute 'fields' not provided"}}
      %{params | error: error}
    end
  end

  defp validate_meta(%{meta: nil} = params), do: params
  defp validate_meta(%{meta: meta} = params) do
    case Helpers.validate_params(meta, Storage.meta_params()) do
      :ok -> params
      {:invalid_param, error} -> %{params | error: {:invalid_param, {:meta, error}}}
    end
  end

  defp validate_nodata(%{nodata: nil} = params), do: params
  defp validate_nodata(%{nodata: nodata} = params) when is_boolean(nodata), do: params
  defp validate_nodata(params) do
    %{params | error: {:invalid_param, {:nodata, "expected a boolean value"}}}
  end
end
