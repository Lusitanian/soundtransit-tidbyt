load("render.star", "render")
load("http.star", "http")
load("cache.star", "cache")
load("encoding/json.star", "json")
load("time.star", "time")


# OneBusAway API Key
API_BASE = "https://api.pugetsound.onebusaway.org/api"
API_KEY = ""

# Station IDs
BEACON_HILL_STATION_NB = "1_99240"
BEACON_HILL_STATION_SB = "1_99121"

def arrivals_and_departures_url(station):
    return API_BASE + "/where/arrivals-and-departures-for-stop/" + station + ".json?key=" + API_KEY + "&minutesAfter=240"

def get_arrivals_and_departures(station):
    cache_key = "departures_reply_" + station
    departures_reply = cache.get(cache_key)
    if departures_reply == None:
        http_reply = http.get(arrivals_and_departures_url(station))
        if http_reply.status_code != 200:
            fail("OneBusAway API HTTP call failed with status %d", http_reply.status_code)
        
        departures_reply = http_reply.json()
        if departures_reply["code"] != 200:
            fail("OneBusAway API returned failure code %d and string %s", departures_reply["code"], departures_reply["text"])
        
        print("Loaded arrivals and departures for ", station)
        cache.set(cache_key, json.encode(departures_reply), ttl_seconds=60)
    else:
        departures_reply = json.decode(departures_reply)
        print("Using cached arrivals and departures for ", station)
    
    return departures_reply

def summarize_departures_by_line(station, skip_departures_with_no_realtime=False, max_results_per_line=2):
    arrivals_and_departures = get_arrivals_and_departures(station)
    result = dict()
    current_timestamp = time.now().unix

    
    for entry in arrivals_and_departures["data"]["entry"]["arrivalsAndDepartures"]:
        has_realtime_tracking = entry["predictedDepartureTime"] != 0
        departure_time = entry["predictedDepartureTime"] if has_realtime_tracking else entry["scheduledDepartureTime"]
        if not has_realtime_tracking and skip_departures_with_no_realtime:
            continue
        
        # Departure timestamp
        departure_time = int(departure_time / 1000)

        # Don't show trains/buses which have already departed
        if departure_time < current_timestamp:
            continue
        
        # Line + direction 
        line_name = entry["routeShortName"].replace("-Line", "")
        line_direction = entry["tripHeadsign"]

        if line_name not in result:
            result[line_name] = dict()
        
        if line_direction not in result[line_name]:
            result[line_name][line_direction] = []
        
        if len(result[line_name][line_direction]) >= max_results_per_line:
            continue
        
        readable_result = str(int( (departure_time - current_timestamp) / 60))
        result[line_name][line_direction].append(readable_result)
    return result

def render_departures(departures):
    next_deps_as_str = "in "

    if len(departures) > 0:
        for i, departure_time in enumerate(departures):
            next_deps_as_str += departure_time
            if i + 2 == len(departures):
                next_deps_as_str += " and "
            elif i + 1 < len(departures):
                next_deps_as_str += ", "
            
    next_deps_as_str += " min"

    return render.Row(children=[
        render.Text(next_deps_as_str, font="CG-pixel-3x5-mono", color="#fa0")
    ])

def render_line_name(line, direction):
    return render.Row(
        cross_align="center",
        main_align="space_between",
        children=[
            render.Circle(diameter=8, color="#0c2689", child=render.Text(line)),
            render.Text(" to " + direction, font="CG-pixel-3x5-mono", color="#63fa0c")
        ]
    )

def spacing_row(h=1):
    return render.Box(height=h)

def main():
    # Get ST Link light rail departures
    northbound_departures = summarize_departures_by_line(BEACON_HILL_STATION_NB)
    southbound_departures = summarize_departures_by_line(BEACON_HILL_STATION_SB)

    # Render
    ui_rows = []

    for line, trips_by_direction in northbound_departures.items():
        for direction, departure_times in trips_by_direction.items():
            ui_rows.append(render_line_name(line, direction))
            ui_rows.append(spacing_row(1))
            ui_rows.append(render_departures(departure_times))

    ui_rows.append(render.Text("--------------------", height=2, font="tom-thumb"))

    for line, trips_by_direction in southbound_departures.items():
        for direction, departure_times in trips_by_direction.items():
            ui_rows.append(render_line_name(line, direction))
            ui_rows.append(spacing_row(1))
            ui_rows.append(render_departures(departure_times))

    
    return render.Root(
        render.Column(
            children=ui_rows
        )
    )

