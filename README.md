# LokiLogger

| **Build Status**                                                      |
|:--------------------------------------------------------------------- |
| [![][gh-actions-img]][gh-actions-url] [![][codecov-img]][codecov-url] |

[Julia][julia-url] client for the [Grafana Loki][loki-url] log aggregation system.


## Usage

If you are not familiar with the logging system in Julia I strongly recommend reading the
[documentation for the `Logging` stdlib][logging-url], and the
[documentation for the `LoggingExtras` package][logextras-url].

`LokiLogger` provides a logging sink, i.e. an end of the logging chain, that pushes the log
events to a Loki server. The only required argument is the Loki logger server URL. It is
possible to configure the logger stream labels (see
[Loki documentation about labels][loki-labels]), and the formatting of the log messages.
Refer to the docstring for `LokiLogger.Logger` for more details.
`LokiLogger` composes nicely with other loggers, in particular
with the various loggers from `LoggingExtras` as seen in the examples below.

### Examples

Basic logger with Loki server on `localhost`:
```julia
using LokiLogger

logger = LokiLogger.Logger("http://localhost:3100")
```

Logger with custom labels and JSON formatting:
```julia
using LokiLogger

logger = LokiLogger.Logger(LokiLogger.json, "http://localhost:3100";
                           labels=Dict("datacenter" => "eu-north", "app" => "my-app"))
```

Composing with `LoggingExtras`:
```julia
using LokiLogger, LoggingExtras

# Create a logger that passes messages to a Loki server running on localhost
logger = TeeLogger(
    global_logger(),
    LokiLogger.Logger("http://localhost:3100"),
)
```

## Installation

Install the package using the package manager (`]` to enter `pkg>` mode):

```
(v1) pkg> add LokiLogger
```


[gh-actions-img]: https://github.com/fredrikekre/LokiLogger.jl/workflows/CI/badge.svg
[gh-actions-url]: https://github.com/fredrikekre/LokiLogger.jl/actions?query=workflow%3ACI

[codecov-img]: https://codecov.io/gh/fredrikekre/LokiLogger.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/fredrikekre/LokiLogger.jl

[julia-url]: https://julialang.org
[loki-url]: https://grafana.com/oss/loki/
[loki-labels]: https://grafana.com/docs/loki/latest/getting-started/labels/
[logging-url]: https://docs.julialang.org/en/v1/stdlib/Logging/
[logextras-url]: https://github.com/oxinabox/LoggingExtras.jl/blob/master/README.md
