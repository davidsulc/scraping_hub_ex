defmodule SHEx.Endpoints.Storage.Items.QueryParams do
  @moduledoc false

  require Logger

  # parameter naming in the API is a bit inconsistent where multi-words variables are concerned
  # (e.g. include_headers vs lineend) and often doesn't conform to the Elixir convention of
  # snake_casing variables composed of multiple words, so this will allow us to accept both (e.g.)
  # `line_end` and `lineend` and convert them to the name the API expects
  @param_synonyms [
    {:includeheaders, :include_headers},
    {:line_end, :lineend},
    {:no_data, :nodata},
    {:start_after, :startafter}
  ]
  @param_synonyms_available @param_synonyms |> Keyword.keys()

  alias SHEx.Endpoints.{Helpers, Storage}

  defstruct [
    :error,
    :nodata,
    :meta,
    format: :json,
    csv_params: [],
    pagination: []
  ]

  def from_keywords(params) when is_list(params) do
    sanitized_params =
      params
      |> sanitize()
      |> configure_pagination()

    case Helpers.validate_params(sanitized_params, [:format, :meta, :nodata, :pagination]) do
      :ok ->
        __MODULE__
        |> struct(sanitized_params)
        |> configure_format()
        |> validate_params()

      error ->
        {:error, error}
    end
  end

  def to_query(%__MODULE__{error: nil} = params) do
    params
    |> Map.from_struct()
    |> Enum.to_list()
    |> Enum.map(&to_keyword_list/1)
    |> List.flatten()
    |> URI.encode_query()
  end

  def to_query(%__MODULE__{error: error}), do: {:error, error}

  defp to_keyword_list({group, params}) when group in [:pagination, :csv_params] do
    params
    |> Enum.map(&to_keyword_list/1)
    |> List.flatten()
  end

  defp to_keyword_list({_, empty}) when empty == nil or empty == [], do: []

  defp to_keyword_list({k, v}) when is_list(v), do: v |> Enum.map(& {k, &1})

  defp to_keyword_list({_, v} = pair) when is_atom(v) or is_integer(v) or is_binary(v), do: pair

  defp to_keyword_list({_, _}), do: []

  defp sanitize(params) when is_list(params) do
    if Keyword.keyword?(params) do
      params |> Enum.map(&sanitize_param/1)
    else
      params
    end
  end

  defp sanitize_param({k, v}) when k in @param_synonyms_available do
    replacement = Keyword.get(@param_synonyms, k)
    Logger.warn("replacing '#{inspect(k)}' parameter with '#{inspect(replacement)}'")
    {replacement, v}
    |> sanitize_param()
  end

  defp sanitize_param({:nodata, false}), do: {:nodata, 0}
  defp sanitize_param({:nodata, true}), do: {:nodata, 1}
  defp sanitize_param({:nodata, v}), do: {:nodata, v}

  defp sanitize_param({k, v}) when is_list(v), do: {k, sanitize(v)}

  defp sanitize_param({_, _} = pair), do: pair

  defp configure_format(params) do
    params |> process_csv_format()
  end

  defp process_csv_format(%{format: format} = params) when is_list(format) do
    if Keyword.keyword?(format) do
      params |> set_csv_attributes()
    else
      error =
        "unexpected list value: #{inspect(format)}"
        |> Helpers.invalid_param_error(:format)

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
          error =
            "multiple values provided: #{inspect(format)}"
            |> Helpers.invalid_param_error(:format)

          %{params | error: error}
        end
    end
  end

  defp configure_pagination(params) do
    pagination_params =
      Storage.pagination_params()
      |> Enum.map(& {&1, Keyword.get(params, &1)})
      |> Enum.reject(fn {_, v} -> v == nil end)

    pagination_list_params = Keyword.get(params, :pagination, [])

    if length(pagination_params) > 0 do
      Logger.warn("pagination values `#{inspect(pagination_params)}` should be provided within the `pagination` parameter")

      common_params = intersection(Keyword.keys(pagination_params), Keyword.keys(pagination_list_params))
      if length(common_params) > 0 do
        Logger.warn("top-level pagination params `#{inspect(common_params)}` will be overridden by values provided in `pagination` parameter")
      end
    end

    pagination = pagination_params |> Keyword.merge(pagination_list_params)

    params
    |> Enum.reject(fn {k, _} -> Enum.member?(Storage.pagination_params(), k) end)
    |> Keyword.put(:pagination, pagination)
  end

  defp intersection(a, b) when is_list(a) and is_list(b) do
    items_only_in_a = a -- b
    a -- items_only_in_a
  end

  defp validate_params(params) do
    params
    |> validate_format()
    |> validate_meta()
    |> validate_nodata()
    |> validate_pagination()
  end

  defp validate_optional_integer_form(nil, _tag), do: :ok

  defp validate_optional_integer_form(value, _tag) when is_integer(value), do: :ok

  defp validate_optional_integer_form(value, tag) when is_binary(value) do
    if String.match?(value, ~r/^\d+$/) do
      :ok
    else
      "expected only digits, was given #{inspect(value)}"
      |> Helpers.invalid_param_error(tag)
    end
  end

  defp validate_optional_integer_form(value, tag) do
    value |> expected_integer_form(tag)
  end

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
      :ok -> params
      {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:csv_param)}
    end
  end

  defp check_fields_param_provided(%{csv_params: csv} = params) do
    if Keyword.has_key?(csv, :fields) do
      params
    else
      error =
        "required attribute 'fields' not provided"
        |> Helpers.invalid_param_error(:csv_param)

      %{params | error: error}
    end
  end

  defp validate_meta(%{meta: nil} = params), do: params

  defp validate_meta(%{meta: meta} = params) when is_list(meta) do
    case Helpers.validate_params(meta, Storage.meta_params()) do
      :ok -> params
      {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:meta)}
    end
  end

  defp validate_meta(params) do
    %{params | error: "expected a list" |> Helpers.invalid_param_error(:meta)}
  end

  defp validate_nodata(%{nodata: nil} = params), do: params
  defp validate_nodata(%{nodata: nodata} = params) when nodata in [0, 1], do: params
  defp validate_nodata(params) do
    %{params | error: "expected a boolean value" |> Helpers.invalid_param_error(:nodata)}
  end

  defp validate_pagination(params) do
    params
    |> validate_pagination_params()
    |> validate_pagination_count()
    |> validate_pagination_start()
    |> validate_pagination_startafter()
    |> process_pagination_index()
    |> validate_pagination_index()
  end

  defp validate_pagination_params(%{pagination: pagination} = params) do
    case Helpers.validate_params(pagination, Storage.pagination_params()) do
      :ok -> params
      {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:pagination)}
    end
  end

  defp validate_pagination_count(%{pagination: pagination} = params) do
    case validate_optional_integer_form(Keyword.get(pagination, :count), :count) do
      :ok -> params
      {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:pagination)}
    end
  end

  defp validate_pagination_start(params), do: params |> validate_pagination_offset(:start)

  defp validate_pagination_startafter(params), do: params |> validate_pagination_offset(:startafter)

  defp validate_pagination_offset(%{pagination: pagination} = params, offset_name) do
    with nil <- Keyword.get(pagination, offset_name) do
      params
    else
      id ->
        case id |> validate_full_form_id(offset_name) do
          :ok -> params
          {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:pagination)}
        end
    end
  end

  defp process_pagination_index(%{pagination: pagination} = params) do
    # the :index key could be given multiple times, so we collect all values into an array
    # which we need to flatten, because it could already have been given as a list
    index =
      pagination
      |> Keyword.get_values(:index)
      |> List.flatten()

    %{params | pagination: pagination |> Keyword.put(:index, index)}
  end

  defp validate_pagination_index(%{pagination: pagination} = params) do
    pagination
    |> Keyword.get(:index)
    |> reduce_indexes_to_first_error()
    |> case do
      :ok -> params
      {:invalid_param, error} -> %{params | error: error |> Helpers.invalid_param_error(:pagination)}
    end
  end

  defp reduce_indexes_to_first_error(indexes) do
    reducer = fn i, acc ->
      case validate_optional_integer_form(i, :index) do
        :ok -> {:cont, acc}
        {:invalid_param, _} = error -> {:halt, error}
      end
    end

    indexes |> Enum.reduce_while(:ok, reducer)
  end

  defp validate_full_form_id(id, tag) when not is_binary(id), do: "expected a string" |> Helpers.invalid_param_error(tag)
  defp validate_full_form_id(id, tag) do
    if id |> String.split("/") |> Enum.reject(& &1 == "") |> length() == 4 do
      :ok
    else
      "expected a full id with exactly 4 parts"
      |> Helpers.invalid_param_error(tag)
    end
  end

  defp expected_integer_form(value, tag) do
    "expected an integer (possibly represented as a string), was given #{inspect(value)}"
    |> Helpers.invalid_param_error(tag)
  end
end
