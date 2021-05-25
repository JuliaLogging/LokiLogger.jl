using Test
import LokiLogger, HTTP, Sockets, JSON3, Logging, URIs

const ch = Channel{Any}(Inf)
function fivexx(http, c=500)
    HTTP.setstatus(http, c)
    HTTP.setheader(http, "Content-Length" => "0")
    HTTP.startwrite(http)
    HTTP.close(http.stream)
end
const server = Sockets.listen(Sockets.InetAddr(Sockets.ip"0.0.0.0", 9100))
tsk = @async HTTP.listen("0.0.0.0", 9100; server=server) do http
    if http.message.method != "POST"
        return fivexx(http)
    end
    ctype = HTTP.header(http.message, "Content-Type")
    if ctype != "application/json"
        return fivexx(http)
    end
    bytes = read(http)
    clength = HTTP.header(http.message, "Content-Length")
    if length(bytes) != parse(Int, clength)
        return fivexx(http)
    end
    try
        put!(ch, JSON3.read(bytes))
    catch
        return fivexx(http)
    end
    # All good
    HTTP.setstatus(http, 204)
    HTTP.startwrite(http)
end
atexit(() -> (close(server); try fetch(tsk) catch e end))
const lokiserver = "http://localhost:9100"
const starttime = time() * 1e9

@testset "LokiLogger.jl" begin
    # Defaults
    logger = LokiLogger.Logger(lokiserver)
    Logging.with_logger(logger) do
        @info "hello, world"
        @error "hello, world" error("hello, error")
    end
    json = take!(ch)
    @test keys(json) == Set([:streams])
    @test length(json.streams) == 1
    @test keys(json.streams[1]) == Set([:stream, :values])
    stream = json.streams[1].stream
    @test stream.host == Sockets.gethostname()
    @test stream.app == "LokiLogger.jl"
    values = json.streams[1].values
    @test length(values) == 1
    @test length(values[1]) == 2
    @test starttime < parse(Int, values[1][1]) < time() * 1e9
    msg = values[1][2]
    @test occursin("level=info msg=\"hello, world\" module=", msg)
    # Error capturing
    json = take!(ch)
    msg = json.streams[1].values[1][2]
    @test occursin("level=error msg=\"Exception while generating log record in module", msg)
    # JSON format
    logger = LokiLogger.Logger(LokiLogger.json, lokiserver; labels=Dict("region" => "eu-central"))
    Logging.with_logger(logger) do
        @error "hello, world" _group=:group
    end
    line = (@__LINE__) - 2
    json = take!(ch)
    @test keys(json) == Set([:streams])
    @test length(json.streams) == 1
    @test keys(json.streams[1]) == Set([:stream, :values])
    stream = json.streams[1].stream
    @test stream.region == "eu-central"
    values = json.streams[1].values
    @test length(values) == 1
    @test length(values[1]) == 2
    @test starttime < parse(Int, values[1][1]) < time() * 1e9
    msg = values[1][2]
    @test occursin("{\"level\":\"error\",\"msg\":\"hello, world\",\"module\":\"", msg)
    msgjson = JSON3.read(msg)
    @test keys(msgjson) == Set([:level, :msg, :module, :file, :line, :group, :id])
    @test msgjson.level == "error"
    @test msgjson.msg == "hello, world"
    @test msgjson.module == "Main"
    @test msgjson.file == @__FILE__
    @test msgjson.line == line
    @test msgjson.group == "group"
    # Custom format
    logger = LokiLogger.Logger(URIs.URI(lokiserver)) do io, args
        println(io, args.level, "| ", args.message)
    end
    Logging.with_logger(logger) do
        @debug "hello, world"
    end
    json = take!(ch)
    msg = json.streams[1].values[1][2]
    @test msg == "Debug| hello, world"
end
