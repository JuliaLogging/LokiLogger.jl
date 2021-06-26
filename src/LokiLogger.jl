module LokiLogger

import HTTP, Logging, StructTypes, JSON3
using URIs: URI

"""
    LokiLogger.Logger(server::Union{String,URI}; labels::Dict)
    LokiLogger.Logger(fmt::Function, server::Union{String,URI}; labels::Dict)

Create a logger that send messages to a Loki server.

The log messages are attributed with the labels given in the `labels` dictionary.
If no labels are specified the default labels are:
 - `"host" => gethostname()`
 - `"app"  => "LokiLogger.jl"`

The `fmt` argument is used for formatting. There are two builtin formatting functions:
 - `LokiLogger.logfmt` (default): formats the log message in the
   [`logfmt`](https://brandur.org/logfmt) format,
 - `LokiLogger.json`: formats the log message as JSON.
Custom functions must take two arguments: an `io::IO` to write the message to,
and `args::NamedTuple` that contains all the logger arguments, see
help for `LoggingExtras.handle_message_args` for details.

## Examples
```julia
# Create a logger with a single label and default (logfmt) formatting
logger = LokiLogger.Logger("http://localhost:3100"; labels = Dict("app" => "myapp"))

# Create a logger with json output formatting
logger = LokiLogger.Logger(LokiLogger.json, "http://localhost:3100")

# Create a logger with custom formatting
logger = LokiLogger.Logger("http://localhost:3100") do io, args
    # Only output the level and the message
    print(io, args.level, ": ", args.message)
end
```
"""
struct Logger <: Logging.AbstractLogger
    server::URI
    labels::Dict{String,String}
    fmt::Function
end

function Logger(fmt::Function, server::Union{String,URI};
                labels::Dict = Dict("host" => gethostname(), "app" => "LokiLogger.jl"))
    return Logger(URI(URI(server); path="/loki/api/v1/push"), labels, fmt)
end
Logger(server::Union{String,URI}; kwargs...) = Logger(logfmt, server; kwargs...)

function Logging.handle_message(loki::Logger, args...; kwargs...)
    log_args = handle_message_args(args...; kwargs...)
    logline = strip(sprint(loki.fmt, log_args))
    json = Dict("streams" => [
        Dict{String,Any}(
            "stream" => loki.labels,
            "values" => [
                String[string(round(Int, time() * 1e9)), logline],
            ]
        )
    ])
    msg = sprint(JSON3.write, json)
    headers = ["Content-Type" => "application/json", "Content-Length" => string(sizeof(msg))]
    # TODO: Implement some kind of flushing timer instead of sending for every message
    HTTP.post(loki.server, headers, msg)
    return nothing
end
Logging.shouldlog(loki::Logger, args...) = true
Logging.min_enabled_level(loki::Logger) = Logging.BelowMinLevel
Logging.catch_exceptions(loki::Logger) = true

# Formats

lvlstr(lvl::Logging.LogLevel) = lvl >= Logging.Error ? "error" :
                                lvl >= Logging.Warn  ? "warn"  :
                                lvl >= Logging.Info  ? "info"  :
                                                       "debug"

## logfmt

"""
    logfmt(io::IO, args)

Format the log message in [`logfmt`](https://brandur.org/logfmt) key-value format
and print to `io`.

Example logline:
```
level=info msg="hello, world" module=Main file="/run.jl" line=2 group=run id=Main_6972c827
```
"""
function logfmt(io::IO, args)
    # TODO: Handle kwargs...
    println(io,
        "level=", lvlstr(args.level),
        " msg=", repr(args.message),
        " module=", string(args._module),
        " file=", repr(args.file),
        " line=", args.line,
        " group=", args.group,
        " id=", args.id
    )
end

## JSON
struct LogMessage
    level::String
    msg::String
    _module::Union{String,Nothing}
    file::Union{String,Nothing}
    line::Union{Int,Nothing}
    group::Union{String,Nothing}
    id::Union{String,Nothing}
end
function LogMessage(args)
    # TODO: Handle kwargs...
    LogMessage(
        lvlstr(args.level),
        args.message,
        args._module === nothing ? nothing : string(args._module),
        args.file,
        args.line,
        args.group === nothing ? nothing : string(args.group),
        # args.id is Tuple{Stackframe,Symbol} for e.g. @depwarn...
        args.id === nothing ? nothing : string(args.id),
    )
end
StructTypes.StructType(::Type{LogMessage}) = StructTypes.OrderedStruct()
StructTypes.names(::Type{LogMessage}) = ((:_module, :module),)
# StructTypes.omitempties(::Type{LogMessage}) = (:_module, :file, :line, :group, :id)

"""
    json(io::IO, args)

Format the log message as JSON and write to `io`.

Example logline:
```
{"level":"info","msg":"hello, world","module":"Main","file":"/run.jl","line":2,"group":"run","id":"Main_6972c827"}
```
"""
function json(io::IO, args)
    logmsg = LogMessage(args)
    JSON3.write(io, logmsg)
    println(io)
end

## Copied from LoggingExtras.jl
## MIT License (https://github.com/oxinabox/LoggingExtras.jl/blob/master/LICENSE.md)
function handle_message_args(args...; kwargs...)
    fieldnames = (:level, :message, :_module, :group, :id, :file, :line, :kwargs)
    fieldvals = (args..., kwargs)
    return NamedTuple{fieldnames, typeof(fieldvals)}(fieldvals)
end

end # module
