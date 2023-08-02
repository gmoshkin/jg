main :: () {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // parse command line arguments
    args := get_command_line_arguments();
    am_server = true;
    connecting = true;
    server_address : string;
    if args.count > 1 {
        if args[1] == {
            case "connect";
                am_server = false;
                if args.count < 3 {
                    log_error("expected a server address");
                    exit(1);
                }
                server_address = args[2];

            case;
                log_error("unexpected command '%'", args[1]);
                exit(1);
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Init connection
    // TODO: move connection initialization into the game loop in a non blocking
    // way, to support event handling in the midst...
    port : u16 = 2276;
    socket_init();
    if am_server {
        // XXX: maybe use UDP, cause TCP seems to be too slow
        listen_sock = socket(AF_INET, .SOCK_STREAM, .TCP);
        if listen_sock == INVALID_SOCKET {
            log_error("Failed creating a socket: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        if !set_blocking(listen_sock, blocking = false) {
            log_error("Failed setting socket to non blocking mode: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        rc := bind(listen_sock, 0, port, AF_INET);
        if rc {
            log_error("`bind` failed on port %: %", port, get_error_string(get_last_socket_error()));
            exit(1);
        }

        rc = listen(listen_sock, 1);
        if rc {
            log_error("`listen` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        log("waiting for a client on port %", port);
        // conn_sock = accept(listen_sock, null, null);
        // if conn_sock == INVALID_SOCKET {
        //     log_error("`accept` failed: %", get_error_string(get_last_socket_error()));
        //     exit(1);
        // }
    } else {
        hints := addrinfo.{ ai_family = AF_INET, ai_socktype = .SOCK_STREAM, ai_protocol = .TCP };
        rc := getaddrinfo(to_c_string(server_address), tprint("%\0", port).data, *hints, *server_addr);
        if rc {
            log_error("`getaddrinfo` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        conn_sock = socket(server_addr.ai_family, server_addr.ai_socktype, server_addr.ai_protocol);
        if conn_sock == INVALID_SOCKET {
            log_error("Failed creating a socket: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        if !set_blocking(conn_sock, blocking = false) {
            log_error("Failed setting socket to non blocking mode: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        log("connecting to the server at %:%", server_address, port);
        // rc = connect(conn_sock, server_addr.ai_addr, xx server_addr.ai_addrlen);
        // if rc {
        //     log_error("`connect` failed: %", get_error_string(get_last_socket_error()));
        //     exit(1);
        // }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Create window
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    window_width  : s32 = 860;
    window_height : s32 = 480;
    window_size : Vector2;
    window := create_window(window_width, window_height, "jg");
    quit := false;

    Simp.set_render_target(window);

    // GetRect stuff
    GetRect.ui_init();
    get_rect_theme := GetRect.default_theme_procs[GetRect.Default_Themes.Default]();
    GetRect.set_default_theme(get_rect_theme);

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Init game state
    entities[0] = .{
        pos = .{ window_width / 2.0 - 100, window_height / 2.0 },
        rot = 0,
        size = .{ 10, 20 },
        collision_radius = 15,
        color = .{ 1, 0, 0, 1 },
        wave_color = .{ 0.8, 0.4, 0.1, 1.0 },
        wave_spawner.waves = array_view(circle_wave_buffer, 0, circle_wave_buffer.count / 2),
    };
    entities[1] = .{
        pos = .{ window_width / 2.0 + 100, window_height / 2.0 },
        rot = 0,
        size = .{ 10, 20 },
        collision_radius = 15,
        color = .{ 0, 0, 1, 1 },
        wave_color = .{ 0.1, 0.4, 0.8, 1.0 },
        wave_spawner.waves = array_view(circle_wave_buffer, circle_wave_buffer.count / 2, circle_wave_buffer.count / 2),
    };
    assert(entities.count == 2, "TODO");

    coin_spawner = .{ coins = coin_buffer };

    // Init network buffers
    net_buf_out.front.capacity    = array_view(net_buffer, BUFFER_SIZE * 0, BUFFER_SIZE);
    net_buf_out.back.capacity     = array_view(net_buffer, BUFFER_SIZE * 1, BUFFER_SIZE);
    net_buf_in.front.data.backing = array_view(net_buffer, BUFFER_SIZE * 2, BUFFER_SIZE);
    net_buf_in.back.capacity      = array_view(net_buffer, BUFFER_SIZE * 3, BUFFER_SIZE * 5);

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Game loop
    while !quit {
        time_start := get_time();

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Handle input
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == window {
                window_width  = it.width;
                window_height = it.height;
                window_size.x = xx window_width;
                window_size.y = xx window_height;
            }
        }

        // Read mouse before checking key presses so that debug_break() is
        // called after we know mouse position.
        mouse : Vector2;
        {
            x, y, ok := get_mouse_pointer_position(window, true);
            if ok {
                mouse.x = xx x;
                mouse.y = xx y;
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            GetRect.getrect_handle_event(it);

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }

                if it.key_pressed && it.key_code == .F4 {
                    do_debug_break();
                }

                if it.key_pressed && it.key_code == .F3 {
                    SHOW_DEBUG_GUI = !SHOW_DEBUG_GUI;
                }
            }
        }

        // GetRect stuff
        GetRect.ui_per_frame_update(window, window_width, window_height, time_start);
        sliders_rect := GetRect.get_rect(xx (window_width - 240), xx (window_height - 30), 200, 20);

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Update/Draw
        Simp.update_window(window);
        Simp.clear_render_target(0.1, 0.1, 0.1, 1);

        // {
        //     light_gray := Vector4.{ 0.6, 0.6, 0.6, 1.0 };
        //     Simp.set_shader_for_color();
        //     len := distance(mouse, it.pos);
        //     thick := 1.0;

        //     to_mouse := mouse - it.pos;
        //     to_mouse_rot := atan2(to_mouse.y, to_mouse.x);
        //     rot_m : Matrix2;
        //     rot_m.v[0] = .{  sin(to_mouse_rot), cos(to_mouse_rot) };
        //     rot_m.v[1] = .{ -cos(to_mouse_rot), sin(to_mouse_rot) };

        //     top_l := (mouse + it.pos) / 2 + multiply(rot_m, .{ -thick, -len / 2 });
        //     bot_l := (mouse + it.pos) / 2 + multiply(rot_m, .{ -thick, +len / 2 });
        //     top_r := (mouse + it.pos) / 2 + multiply(rot_m, .{ +thick, -len / 2 });
        //     bot_r := (mouse + it.pos) / 2 + multiply(rot_m, .{ +thick, +len / 2 });

        //     Simp.immediate_quad(
        //         top_l, bot_l, bot_r, top_r,
        //         light_gray, light_gray, light_gray, light_gray,
        //     );
        // }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Update it
        if am_server {
            my_index = 0; their_index = 1;
        } else {
            my_index = 1; their_index = 0;
        }
        mouses[my_index] = mouse;
        if last_received.ready {
            mouses[their_index] = last_received.mouse;
        } else if !have_human_player {
            closest_distance := FLOAT32_INFINITY;
            closest_coin : *Coin = null;
            for * coin: coin_buffer {
                if !coin.is_enabled then continue;
                d := distance(coin.origin, entities[their_index].pos);
                if d < closest_distance {
                    closest_distance = d;
                    closest_coin = coin;
                }
            }
            if closest_coin {
                mouses[their_index] = closest_coin.origin;
            } else {
                time_now := get_time();
                if time_now > time_when_last_random_mouse_position_was_chosen + TIME_BETWEEN_RANDOM_MOUSE_POSITION_PICKS {
                    time_when_last_random_mouse_position_was_chosen = time_now;
                    x := random_get_zero_to_one() * window_width;
                    y := random_get_zero_to_one() * window_height;
                    mouses[their_index] = .{ x, y };
                }
            }
        }

        // TODO: factor this into a loop where each ship is targetting it's
        // corresponding mouse. Our mouse is just `mouse`, their mouse is
        // 1. If not connected yet, do the random mouse movements simulation
        // 2. If connected, do last mouse position or maybe extrapolate mouse
        // movements. We can extrapolate linearly or maybe something better?
        for * entities {
            to_mouse := mouses[it_index] - it.pos;
            to_rot := atan2(to_mouse.y, to_mouse.x);

            rot_delta := to_rot - it.rot;
            if rot_delta > PI || rot_delta < -PI rot_delta = -rot_delta;
            rot_delta = clamp(rot_delta, -ROT_SPEED, ROT_SPEED);

            it.rot = it.rot + rot_delta;
            while it.rot > +PI  it.rot -= 2 * PI;
            while it.rot < -PI  it.rot += 2 * PI;

            rot_m : Matrix2;
            rot_m.v[0] = .{  sin(it.rot), cos(it.rot) };
            rot_m.v[1] = .{ -cos(it.rot), sin(it.rot) };

            it.pos += MOV_SPEED * multiply(rot_m, .{ 0, 1 });
        }

        // DEBUG
        if Input.input_button_states[#char "0"] == .DOWN {
            entities[my_index].pos = .{ xx (window_width / 2), xx (window_height / 2) };
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Update circle waves

        for * circle_wave_buffer {
            if !it.is_enabled continue;

            it.outer_radius += RADIUS_DELTA;
            if it.outer_radius > MAX_RADIUS {
                it.is_enabled = false;
            }

            it.strength *= FADE_AWAY_FACTOR;
        }

        time_now := get_time();

        for * entities {
            if time_now - it.wave_spawner.time_when_last_one_spawned > TIME_BETWEEN_CIRCLE_WAVE_SPAWNS {
                // TODO: send wave data over network also
                it.wave_spawner.waves[it.wave_spawner.current_index] = circle_wave(it.pos, it.wave_color, is_enabled=true);
                it.wave_spawner.current_index += 1;
                if it.wave_spawner.current_index >= it.wave_spawner.waves.count then
                    it.wave_spawner.current_index = 0;

                it.wave_spawner.time_when_last_one_spawned = time_now;
            }
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Wave collisions

        for * ship: entities {
            rot_delta := 0.0;

            for * wave: circle_wave_buffer {
                if !wave.is_enabled continue;

                if wave.outer_radius < WAVE_WEAK_UNTIL_RADIUS continue;

                pos_diff := ship.pos - wave.origin;
                distance_squared := pos_diff.x * pos_diff.x + pos_diff.y * pos_diff.y;
                wave_inner_radius := wave.outer_radius - wave.width;
                if distance_squared > wave.outer_radius * wave.outer_radius ||
                   distance_squared < wave_inner_radius * wave_inner_radius
                {
                    continue;
                }

                to_wave_center := atan2(pos_diff.y, pos_diff.x);
                tangentality_to_wave := to_wave_center - ship.rot;

                wave_force := WAVE_STRENGTH * wave.strength * sin(tangentality_to_wave);

                // TODO: do this when computing rot_delta in the first place
                rot_delta += wave_force;
            }

            rot_delta = clamp(rot_delta, -WAVE_ROT_CLAMP, WAVE_ROT_CLAMP);
            ship.rot += rot_delta;
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Coin spawning

        time_now = get_time();

        assert(Coin_Spawner_Parameters.max_live_ones < coin_buffer.count);
        if time_now > coin_spawner.time_when_last_one_spawned + Coin_Spawner_Parameters.spawn_period
            && coin_spawner.n_live_ones < Coin_Spawner_Parameters.max_live_ones
        {
            using coin_spawner;
            x := random_get_zero_to_one() * window_width;
            y := random_get_zero_to_one() * window_height;
            coins[current_index] = Coin.with_defaults(.{ x, y });

            current_index += 1;
            if current_index >= coins.count then current_index = 0;
            n_live_ones += 1;

            // Don't overwrite a live coin
            while coins[current_index].is_enabled {
                current_index += 1;
                if current_index >= coins.count then current_index = 0;
            }

            time_when_last_one_spawned = time_now;
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Coin collisions

        for * ship, ship_index: entities {
            for * coin: coin_buffer {
                if !coin.is_enabled then continue;
                if distance(coin.origin, ship.pos) > coin.radius + ship.collision_radius then continue;
                coin.is_enabled = false;
                score_board.points[ship_index] += 1;
                coin_spawner.n_live_ones -= 1;
            }
        }


        if last_received.ready {
            have_human_player = true;
            // Override the data we just simulated
            mouses[their_index] = last_received.mouse;

            ship := *entities[their_index];
            ship.base = last_received.ship;

            waves := *entities[their_index].wave_spawner.waves;
            for 0..last_received.waves_count-1 {
                waves.*[it].base = last_received.waves[it];
                waves.*[it].is_enabled = true;
            }
            for last_received.waves_count..waves.count-1 {
                waves.*[it].is_enabled = false;
            }

            if !am_server {
                coins := *coin_spawner.coins;
                for 0..last_received.coins_count-1 {
                    coins.*[it].base = last_received.coins[it];
                    coins.*[it].is_enabled = true;
                }
                for last_received.coins_count..coins.count-1 {
                    coins.*[it].is_enabled = false;
                }
            }
        }


        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Draw
        Simp.set_shader_for_color(enable_blend = true);

        // Rotation matrices for drawing circly stuff
        N :: 32;
        rot_m : [N] Matrix2 : #run -> [N] Matrix2 {
            rot_m : [N] Matrix2;
            for k: 0..N-1 {
                rot_m[k].v[0] = .{  sin(k * TAU / N), cos(k * TAU / N) };
                rot_m[k].v[1] = .{ -cos(k * TAU / N), sin(k * TAU / N) };
            }
            return rot_m;
        };

        // Circle waves
        {
            draw_circle_wave :: (draw_weak_ones := false) #expand {
                it := `it;
                k := `k;
                if !it.is_enabled continue;
                top_l := it.origin + multiply(rot_m[k],         .{ 0, it.outer_radius });
                bot_l := it.origin + multiply(rot_m[k],         .{ 0, it.outer_radius - it.width });
                top_r := it.origin + multiply(rot_m[(k + 1) % N], .{ 0, it.outer_radius });
                bot_r := it.origin + multiply(rot_m[(k + 1) % N], .{ 0, it.outer_radius - it.width });

                color := it.color;
                if it.outer_radius < WAVE_WEAK_UNTIL_RADIUS {
                    if !draw_weak_ones continue;
                    color.xyz *= .5;
                } else {
                    if draw_weak_ones continue;
                }
                color.w = it.strength;

                Simp.immediate_quad(
                    top_l, top_r, bot_r, bot_l,
                    color, color, color, color,
                );
            }

            // Draw strong ones first so that weak ones are drawn correctly over
            for k: 0..N-1 for * circle_wave_buffer {
                draw_circle_wave(draw_weak_ones = false);
            }

            for k: 0..N-1 for * circle_wave_buffer {
                draw_circle_wave(draw_weak_ones = true);
            }
        }

        for k: 0..N-1 {
            for * coin_buffer {
                if !it.is_enabled continue;

                draw_coin :: (coin: *Coin, k: s64) #expand {
                    o := coin.origin;
                    a := coin.origin + multiply(rot_m[k],           .{ 0, coin.radius });
                    b := coin.origin + multiply(rot_m[(k + 1) % N], .{ 0, coin.radius });

                    Simp.immediate_triangle(
                        .{ xy = o }, .{ xy = a }, .{ xy = b },
                        coin.color, coin.color, coin.color,
                    );
                }

                draw_coin(it, k);
            }
        }

        Simp.immediate_quad(
            mouses[their_index] + .{ -ADVERSARY_MOUSE.size / 2, -ADVERSARY_MOUSE.size / 2 },
            mouses[their_index] + .{ -ADVERSARY_MOUSE.size / 2, +ADVERSARY_MOUSE.size / 2 },
            mouses[their_index] + .{ +ADVERSARY_MOUSE.size / 2, +ADVERSARY_MOUSE.size / 2 },
            mouses[their_index] + .{ +ADVERSARY_MOUSE.size / 2, -ADVERSARY_MOUSE.size / 2 },
            ADVERSARY_MOUSE.color, ADVERSARY_MOUSE.color, ADVERSARY_MOUSE.color, ADVERSARY_MOUSE.color,
        );

        for * entities {
            Simp.set_shader_for_color();

            rot_m : Matrix2;
            rot_m.v[0] = .{  sin(it.rot), cos(it.rot) };
            rot_m.v[1] = .{ -cos(it.rot), sin(it.rot) };

            top_l := it.pos + multiply(rot_m, .{ - it.size.x / 2, - it.size.y / 2 });
            top_r := it.pos + multiply(rot_m, .{ - it.size.x / 2, + it.size.y / 2 });
            bot_l := it.pos + multiply(rot_m, .{ + it.size.x / 2, + it.size.y / 2 });
            bot_r := it.pos + multiply(rot_m, .{ + it.size.x / 2, - it.size.y / 2 });

            Simp.immediate_quad(
                top_l, top_r, bot_l, bot_r,
                it.color, it.color, it.color, it.color,
            );

            // sliders_rect.y -= 20;
            // GetRect.slider(sliders_rect, *ARROW.OFS, -2, +2, 4 / 100, *get_rect_theme.slider_theme, "ARROW.OFS ");
            //
            // sliders_rect.y -= 20;
            // GetRect.slider(sliders_rect, *ARROW.LEN, -2, +2, 4 / 100, *get_rect_theme.slider_theme, "ARROW.LEN ");
            //
            // sliders_rect.y -= 20;
            // GetRect.slider(sliders_rect, *ARROW.SPAN, -2, +2, 4 / 100, *get_rect_theme.slider_theme, "ARROW.SPAN ");

            head_tip   := it.pos + multiply(rot_m, .{ 0, it.size.y * ARROW.OFS + it.size.y * ARROW.LEN });
            head_left  := it.pos + multiply(rot_m, .{ -it.size.x * ARROW.SPAN / 2, it.size.y * ARROW.OFS });
            head_right := it.pos + multiply(rot_m, .{ +it.size.x * ARROW.SPAN / 2, it.size.y * ARROW.OFS });

            Simp.immediate_triangle(
                .{ xy = head_tip },
                .{ xy = head_left },
                .{ xy = head_right },
                it.color, it.color, it.color,
            );
        }

        {
            x := window_size.x / 2 - 50;
            y := window_size.y - 50;
            r := GetRect.get_rect(x, y, 100, 20);
            GetRect.label(r, tprint("%", score_board.points[red_ship_id]), *get_rect_theme.label_theme);

            r.x += 30;
            GetRect.label(r, tprint("%", score_board.points[blue_ship_id]), *get_rect_theme.label_theme);
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Global variables debug editing
        if SHOW_DEBUG_GUI {

            r := GetRect.get_rect(10, xx (window_height - 20), 300, 20);
            GetRect.slider(r, *ROT_SPEED, 0.0, 0.1, 0.005, *get_rect_theme.slider_theme, "ROT_SPEED ");

            r.y -= 20;
            GetRect.slider(r, *MOV_SPEED, 0.0, 10, 0.5, *get_rect_theme.slider_theme, "MOV_SPEED ");

            r.y -= 20;
            GetRect.slider(r, *MAX_RADIUS, 0.0, 500, 10.0, *get_rect_theme.slider_theme, "MAX_RADIUS ");

            r.y -= 20;
            GetRect.slider(r, *RADIUS_DELTA, 0.0, 20, 1.0, *get_rect_theme.slider_theme, "RADIUS_DELTA ");

            r.y -= 20;
            GetRect.slider(r, *TIME_BETWEEN_CIRCLE_WAVE_SPAWNS, 0.0, 1, 0.02, *get_rect_theme.slider_theme, "WAVE_SPAWN_PERIOD ");

            r.y -= 20;
            GetRect.slider(r, *FADE_AWAY_FACTOR, 0.0, 1, 1./255, *get_rect_theme.slider_theme, "FADE_AWAY_FACTOR ");

            r.y -= 20;
            GetRect.slider(r, *WAVE_STRENGTH, 0.0, 1, 1./255, *get_rect_theme.slider_theme, "WAVE_STRENGTH ");

            r.y -= 20;
            GetRect.slider(r, *WAVE_ROT_CLAMP, 0.0, PI, PI / 36, *get_rect_theme.slider_theme, "WAVE_ROT_CLAMP ");

            r.y -= 20;
            GetRect.slider(r, *WAVE_WEAK_UNTIL_RADIUS, 0.0, 500.0, 10.0, *get_rect_theme.slider_theme, "WEAK_RAD ");

        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Main loop end
        Simp.swap_buffers(window);

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Network IO
        frame_budget_secs := 1.0 / 60;
        networking(time_start + frame_budget_secs);

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // End of frame
        reset_temporary_storage();

        secs_spent_so_far := get_time() - time_start;
        secs_left := frame_budget_secs - secs_spent_so_far;
        if secs_left > 0 {
            // log("going to sleep for %", millis_left_to_sleep, flags = .VERY_VERBOSE_ONLY);
            sleep_milliseconds(xx (secs_left * 1000));
        } else {
            // log("we're running late, not gonna sleep tonight", flags = .VERY_VERBOSE_ONLY);
        }
    }
}

TARGET_FPS := 60;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Entity stuff
ARROW : struct {
    OFS := .21;
    LEN := .88;
    SPAN := 1.69;
};

ADVERSARY_MOUSE : struct {
    size := 5.0;
    color := Vector4.{ 0.3, 0.3, 0.3, 1.0 };
};

ROT_SPEED := .1;
MOV_SPEED := 3.0;

//
// Ships
//
N_ENTITIES :: 2;
entities : [N_ENTITIES] Entity;

my_index : s32;
their_index : s32;

red_ship_id :: 0;
blue_ship_id :: 1;
mouses : [entities.count] Vector2;

Entity :: struct {
    // Fields we send over network
    Base :: struct {
        pos: Vector2;
        rot: f32;
    }
    using base: Base;

    size: Vector2;
    color: Vector4;
    wave_color: Vector4;
    is_enabled: bool;
    wave_spawner: CircleWaveSpawner;
    collision_radius: f32;
};

//
// Waves
//
CircleWaveSpawner :: struct {
    waves: [] CircleWave;
    current_index: s32;
    time_when_last_one_spawned: f64;
};

CircleWave :: struct {
    // Fields we send over network
    Base :: struct {
        origin: Vector2;
        outer_radius: f32;
        strength: f32;
    }
    using base: Base;

    color: Vector4;
    width: f32;
    is_enabled: bool = false;
};

circle_wave :: inline (origin: Vector2, color: Vector4, is_enabled: bool = true) -> CircleWave {
    return .{
        origin = origin,
        is_enabled = is_enabled,
        outer_radius = INITIAL_OUTER_RADIUS,
        strength = 1,
        color = color,
        width = WAVE_WIDTH,
    };
}

MAX_CIRCLE_WAVES_VISIBLE_AT_A_TIME_PER_ENTITY :: 32;
N_CIRCLE_WAVES :: MAX_CIRCLE_WAVES_VISIBLE_AT_A_TIME_PER_ENTITY * entities.count;
circle_wave_buffer : [N_CIRCLE_WAVES] CircleWave;

//
// Coins
//
Coin_Spawner :: struct {
    coins: [] Coin;
    current_index: s32;
    time_when_last_one_spawned: f64;
    n_live_ones: s32;
}
coin_spawner : Coin_Spawner;

Coin_Spawner_Parameters : struct {
    spawn_period : f64 = 2.0;
    default_radius : f32 = 10.0;
    default_color := Vector4.{ 1.0, 0.8, 0.0, 1 };
    max_live_ones : s32 = 4;
};

Coin :: struct {
    // Fields we send over network
    Base :: struct {
        origin: Vector2;
    };
    using base: Base;

    radius: f32;
    color: Vector4;
    is_enabled: bool = false;

    with_defaults :: (_origin: Vector2) -> Coin {
        return .{
            origin = _origin,
            radius = Coin_Spawner_Parameters.default_radius,
            color = Coin_Spawner_Parameters.default_color,
            is_enabled = true,
        };
    }
}

COIN_BUFFER_COUNT :: 32;
coin_buffer : [COIN_BUFFER_COUNT] Coin;

//
// Score board
//

Score_Board :: struct {
    points : [entities.count] s32;
}
score_board : Score_Board;

//
// Parameters
//
SHOW_DEBUG_GUI := false;
TIME_BETWEEN_CIRCLE_WAVE_SPAWNS := 0.16;
MAX_RADIUS := 400.;
RADIUS_DELTA := 1.;
FADE_AWAY_FACTOR := 0.97;
WAVE_STRENGTH := 0.97;
WAVE_ROT_CLAMP := PI / 9;
WAVE_WEAK_UNTIL_RADIUS := 40.;
INITIAL_OUTER_RADIUS := 10.;
WAVE_WIDTH : f32 = 10.;

TIME_BETWEEN_RANDOM_MOUSE_POSITION_PICKS := 2;
time_when_last_random_mouse_position_was_chosen : f64;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Network stuff

networking :: (deadline: f64) {
    Check_Timeout :: () #expand {
        if get_time() > deadline `return;
    }

    Check_Timeout();

    // TODO: this actually takes a lot of time, probably best not to do it every frame
    if connecting {
        if am_server {
            // TODO: .VERY_VERBOSE_ONLY doesn't seem to do what I expected, gotta go investigate
            // log("checking if somebody connected...", flags = .VERY_VERBOSE_ONLY);
            conn_sock = accept(listen_sock, null, null);
            if conn_sock == INVALID_SOCKET {
                err := get_last_socket_error();
                if err != SOCKET_WOULDBLOCK  log_error("`accept` failed: #% %", err, get_error_string(err));
                // log("no connection yet", flags = .VERY_VERBOSE_ONLY);
            } else {
                log("got a connection", flags = .VERY_VERBOSE_ONLY);
                connecting = false;
            }
        } else /* am_client */ {
            rc := connect(conn_sock, server_addr.ai_addr, xx server_addr.ai_addrlen);
            if rc {
                err := get_last_socket_error();
                if err != SOCKET_WOULDBLOCK {
                    ignore := false;
                    #if OS == .WINDOWS {
                        // XXX: am I doing something wrong, or why would we get here?
                        if err == WSAEISCONN   connecting = false;
                        if err == WSAEALREADY  ignore = true;
                    }
                    if connecting && !ignore  log_error("`connect` failed: #% %", err, get_error_string(err));
                }
            } else {
                connecting = false;
            }
        }
    }

    Check_Timeout();

    last_received.ready = false;
    disconnected := false;

    defer {
        if disconnected {
            if am_server {
                log_error("lost connection to client, will listen for more connections...");
            } else /* am_client */ {
                log_error("lost connection to server, will retry connecting...");
                // TODO: the socket should be closed and reinitialized
            }
            connecting = true;

            net_buf_out.back.pending.count = 0;
            reset(*net_buf_in.front.data);
            net_buf_in.front.packet_size = 0;
        }
    }

    if !connecting {
        // Serialize current state to the front buffer
        net_buf_out.front.pending = serialize_to_send(net_buf_out.front.capacity, my_index);

        while true {
            // if get_time() < last_packet_sent_time + 1 / cast(float) packets_sent_per_second break;
            if disconnected return;
            Check_Timeout();

            if !net_buf_out.back.pending {
                Swap(*net_buf_out.front, *net_buf_out.back);
                if !net_buf_out.back.pending break;
                sync += 1;
                copy(net_buf_out.back.pending.data + 4, *sync);
            }

            n_bytes_sent, _disconnected := send_slice(net_buf_out.back.pending);
            disconnected |= _disconnected;

            if n_bytes_sent {
                Setup_Mem_Dump_Printer();
                log(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
                log("sent packet:");
                log("%", cast(Mem_Dump) array_view(net_buf_out.back.pending, 0, n_bytes_sent));
                log(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
            }

            if !n_bytes_sent break;
            advance(*net_buf_out.back.pending, n_bytes_sent);

            if net_buf_out.back.pending {
                // failed to send whole buffer ->  will retry next time
                break;
            } else {
                // sent whole buffer
                last_packet_sent_time = get_time();
            }
        }

        should_be_receiving_packets := true;
        while should_be_receiving_packets {
            if disconnected return;
            Check_Timeout();

            n_bytes_received, _disconnected := receive_slice(net_buf_in.back.capacity);
            disconnected |= _disconnected;

            if n_bytes_received {
                Setup_Mem_Dump_Printer();
                log("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
                log("received data:");
                log("%", cast(Mem_Dump) array_view(net_buf_in.back.capacity, 0, n_bytes_received));
                log("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<");
            }

            if !n_bytes_received break;

            last_time_received_something = get_time();

            // Didn't fill up the buffer -> received all there was to receive
            if n_bytes_received != net_buf_in.back.capacity.count then should_be_receiving_packets = false;

            received_slice := array_view(net_buf_in.back.capacity, 0, n_bytes_received);
            while received_slice {
                log_dbg(net_buf_in.front.packet_size);
                packet_piece_size := 0;
                if net_buf_in.front.packet_size {
                    packet_piece_size = net_buf_in.front.packet_size - count(*net_buf_in.front.data);
                } else {
                    packet_size := read_packet_header(received_slice);
                    log_dbg(packet_size);
                    pretty_assert(packet_size > 0);
                    net_buf_in.front.packet_size = packet_size;

                    packet_piece_size = min(packet_size, xx received_slice.count);
                }
                log_dbg(packet_piece_size);
                packet_piece := array_view(received_slice, 0, packet_piece_size);
                append(*net_buf_in.front.data, packet_piece);
                advance(*received_slice, packet_piece_size);

                ring_buffer_count := count(*net_buf_in.front.data);
                log_dbg(ring_buffer_count);
                log_dbg(net_buf_in.front.packet_size);
                if ring_buffer_count != net_buf_in.front.packet_size break;

                n_bytes_consumed, consumed := deserialize_received_data(net_buf_in.front.data.backing, their_index);
                assert(consumed);
                pretty_assert(n_bytes_consumed == count(*net_buf_in.front.data));

                reset(*net_buf_in.front.data);
                net_buf_in.front.packet_size = 0;
            }
        }

        if last_time_received_something > 0 && get_time() - last_time_received_something > 1 {
            debug_break();
        }
    }
}

sync : s32 = 0;
last_time_received_something : f64 = -1;

read_packet_header :: (buffer: [] u8) -> packet_size: s32 {
    if buffer.count < 16 then return -1;

    magic : [4] u8;
    memcpy(magic.data, buffer.data, size_of(type_of(magic)));
    pretty_assert(array_equals(magic, MAGIC));

    packet_size : s32;
    memcpy(*packet_size, buffer.data + 4 + 4, size_of(s32));

    return packet_size;
}

send_slice :: (slice: [] u8) -> n_bytes_sent: s64, need_reconnect : bool {
    rc := send(conn_sock, slice.data, xx slice.count, 0);
    if rc < 0 {
        need_reconnect := false;
        err := get_last_socket_error();
        if err != SOCKET_WOULDBLOCK  {
            log_error("Failed sending to socket: #% %", err, get_error_string(err));
            #if OS == .WINDOWS {
                need_reconnect = (err == WSAECONNRESET);
            } else {
                // TODO: always need_reconnect = true??
            }
        }
        return 0, need_reconnect;
    }

    return rc, false;
}

// FIXME: copypaste
receive_slice :: (slice: [] u8) -> n_bytes_received: s64, need_reconnect: bool {
    rc := recv(conn_sock, slice.data, xx slice.count, 0);

    Handle_Error :: (rc: s32) #expand {
        if rc < 0 {
            need_reconnect := false;
            err := get_last_socket_error();
            if err != SOCKET_WOULDBLOCK  {
                log_error("Failed receiving from socket: #% %", err, get_error_string(err));
                #if OS == .WINDOWS {
                    need_reconnect = (err == WSAECONNRESET);
                } else {
                    // TODO: always need_reconnect = true??
                }
            }
            `return 0, need_reconnect;
        }
    }
    Handle_Error(rc);

    return rc, false;
}

MAGIC :: u8.[ 0xb0, 0x00, 0xb1, 0xe5 ];

serialize_to_send :: (buffer: [] u8, entity_id: s32) -> written_slice: [] u8 {
    copy_and_advance :: (slice: *[] u8, v: *$T) #expand {
        assert(slice.count >= size_of(T));
        memcpy(slice.data, v, size_of(T));
        advance(slice, size_of(T));
    }

    slice := buffer;


    copy_and_advance(*slice, *MAGIC);

    sync: s32 = 0;
    copy_and_advance(*slice, *sync);

    packet_size : s32 = 0;
    p_packet_size := slice.data;
    copy_and_advance(*slice, *packet_size);


    copy_and_advance(*slice, *cast([4] u8) "\x11\x11\x11\x11");
    copy_and_advance(*slice, *mouses[entity_id]);
    ship := *entities[entity_id];
    copy_and_advance(*slice, *cast([4] u8) "\x22\x22\x22\x22");
    copy_and_advance(*slice, *ship.pos);
    copy_and_advance(*slice, *ship.rot);


    waves_count : s32 = 0;
    copy_and_advance(*slice, *cast([4] u8) "\x33\x33\x33\x33");
    p_waves_count := slice.data;
    copy_and_advance(*slice, *waves_count);
    for * wave: ship.wave_spawner.waves {
        if !wave.is_enabled continue;

        waves_count += 1;
        copy_and_advance(*slice, *wave.origin);
        copy_and_advance(*slice, *wave.outer_radius);
        copy_and_advance(*slice, *wave.strength);
    }
    copy(p_waves_count, *waves_count);


    coins_count : s32 = 0;
    copy_and_advance(*slice, *cast([4] u8) "\x44\x44\x44\x44");
    p_coins_count := slice.data;
    copy_and_advance(*slice, *coins_count);
    if am_server {
        for * coin: coin_buffer {
            if !coin.is_enabled continue;

            coins_count += 1;
            copy_and_advance(*slice, *coin.origin);
        }
        copy(p_coins_count, *coins_count);
    }


    res: [] u8 = ---;
    res.data = buffer.data;
    res.count = slice.data - buffer.data;

    packet_size = xx res.count;
    copy(p_packet_size, *packet_size);

    return res;
}

deserialize_received_data :: (buffer: [] u8, entity_id: s32) -> n_bytes_consumed: s32, deserialized_full_packet: bool {
    try_read_and_advance :: (slice: *[] u8, v: *$T) #expand {
        if slice.count < size_of(T) `return 0, false;
        memcpy(v, slice.data, size_of(T));
        advance(slice, size_of(T));
    }

    slice := buffer;


    magic : [4] u8;
    try_read_and_advance(*slice, *magic);
    assert(array_equals(magic, MAGIC));
    // log("read magic");

    sync: s32;
    try_read_and_advance(*slice, *sync);
    // log_dbg(sync);

    packet_size : s32;
    try_read_and_advance(*slice, *packet_size);
    // log_dbg(packet_size);


    try_read_and_advance(*slice, *magic);
    assert(array_equals(magic, xx "\x11\x11\x11\x11"));
    try_read_and_advance(*slice, *last_received.mouse);
    // log_dbg(last_received.mouse);

    try_read_and_advance(*slice, *magic);
    assert(array_equals(magic, xx "\x22\x22\x22\x22"));
    try_read_and_advance(*slice, *last_received.ship.pos);
    // log_dbg(last_received.ship.pos);
    try_read_and_advance(*slice, *last_received.ship.rot);
    // log_dbg(last_received.ship.rot);


    try_read_and_advance(*slice, *magic);
    assert(array_equals(magic, xx "\x33\x33\x33\x33"));
    try_read_and_advance(*slice, *last_received.waves_count);
    // log_dbg(last_received.waves_count);
    assert(last_received.waves_count <= last_received.waves.count);
    for 0..last_received.waves_count-1 {
        wave := *last_received.waves[it];
        try_read_and_advance(*slice, *wave.origin);
        try_read_and_advance(*slice, *wave.outer_radius);
        try_read_and_advance(*slice, *wave.strength);
        // log_dbg(it);
        // log_dbg(wave.*);
    }

    try_read_and_advance(*slice, *magic);
    assert(array_equals(magic, xx "\x44\x44\x44\x44"));
    try_read_and_advance(*slice, *last_received.coins_count);
    // log_dbg(last_received.coins_count);
    assert(last_received.coins_count <= last_received.coins.count);
    for 0..last_received.coins_count-1 {
        coin := *last_received.coins[it];
        try_read_and_advance(*slice, *coin.origin);
        // log_dbg(it);
        // log_dbg(coin.origin);
    }

    last_received.ready = true;
    n_bytes_consumed := slice.data - buffer.data;
    return xx n_bytes_consumed, true;
}

last_received : struct {
    ship : Entity.Base;
    mouse : Vector2;
    waves : [MAX_CIRCLE_WAVES_VISIBLE_AT_A_TIME_PER_ENTITY] CircleWave.Base;
    waves_count : s32;
    coins : [coin_buffer.count] Coin.Base;
    coins_count : s32;
    ready : bool;
};

am_server : bool;
have_human_player : bool;
connecting : bool;
server_addr : *addrinfo;

conn_sock : Socket;
listen_sock : Socket;

packets_sent_per_second := 30;
last_packet_sent_time : f64 = 0.0;

BUFFER_SIZE :: 1024;

net_buffer : [BUFFER_SIZE * 8] u8;
IO_Buffer :: struct {
    capacity: [] u8;
    pending: [] u8;
}

/*

empty:
[. . . . . . . .]
 ^
 end:0
 start:0
 empty = true

push_back(1):
[1 . . . . . . .]
 ^ ^
 | end:1
 start:0
 empty = false

push_back(2):
[1 2 . . . . . .]
 ^   ^
 |   end:2
 start:0
 empty = false

pop_front() -> 1:
[. 2 . . . . . .]
   ^ ^
   | end:2
   start:1
 empty = false

push_front(3):
[3 2 . . . . . .]
 ^   ^
 |   end:2
 start:0
 empty = false

push_front(4):
[3 2 . . . . . 4]
     ^         ^
     end:2     |
               start:7
 empty = false

push_front(5),
push_back(6),
push_front(8),
push_back(7),
push_back(0):
[3 2 6 7 0 8 5 4]
           ^
           end:
           start
 empty = false

pop_front() -> 8:
[3 2 6 7 0 . 5 4]
           ^ ^
           end:5
             start:6

 */
Ring_Buffer :: struct {
    backing: [] u8;
    start: s32;
    end: s32;
    // TODO: store count directly instead
    is_empty: bool = true;
}

reset :: inline (using rb: *Ring_Buffer) {
    start, end = 0;
    is_empty = true;
}

is_empty :: inline (using rb: *Ring_Buffer) -> bool {
    return is_empty;
}

is_full :: inline (using rb: *Ring_Buffer) -> bool {
    return start == end && !is_empty;
}

count :: inline (using rb: *Ring_Buffer) -> s32 {
    if is_empty         return 0;
    else if end > start return end - start;
    else                return end - start + xx backing.count;
}

capacity :: inline (using rb: *Ring_Buffer) -> s32 {
    return xx backing.count - count(rb);
}

push_back :: inline (using rb: *Ring_Buffer, v: u8) {
    assert(capacity(rb) >= 1);
    backing[end] = v;
    end = (end + 1) % xx backing.count;
    is_empty = false;
}

append :: inline (using rb: *Ring_Buffer, data: [] u8) {
    assert(capacity(rb) >= data.count);
    // TODO: optimize
    for data push_back(rb, it);
}

// // May not return all the free space in the buffer, because you know why
// back_slice :: (using rb: *Ring_Buffer) -> [] u8 {
//     res : u8[] = ---;
//     res.data = backing.data + end;
//     if end >= start then
//         // TODO: if end == count
//         res.count = (backing.count - end) * is_empty;
//     else
//         res.count = start - end;
//     return res;
// }

// advance_back :: (using rb: *Ring_Buffer, count: s32) {
//     assert(back_slice(rb).count >= count);
//     end += count;
// }

IO_Buffer_Pair :: struct {
    front: IO_Buffer;
    back: IO_Buffer;
}

net_buf_in : struct {
    front: struct {
        data: Ring_Buffer;
        packet_size: s32;
    };
    back: IO_Buffer;
};

net_buf_out : IO_Buffer_Pair;

Network_Packet_Header :: struct {
    mouse: Vector2;
    ship_pos: Vector2;
    ship_rot: f32;
} #no_padding;

f32 :: float32;
f64 :: float64;

array_equals :: (lhs: [$N] $T, rhs: [N] T) -> bool {
    for lhs {
        if rhs[it_index] != it return false;
    }
    return true;
}

advance :: inline (a: *[] $T, count: s64) {
    pretty_assert(count >= 0);
    pretty_assert(a.count >= count);
    a.count -= count;
    a.data  += count;
}

advance :: inline (a: [] $T, count: s64) -> [] T #must {
    pretty_assert(count >= 0);
    pretty_assert(a.count >= count);

    res: [] $T = ---;
    res.count = a.count - count;
    res.data  = a.data  + count;
    return res;
}

copy :: inline (p: *u8, v: *$T) {
    memcpy(p, v, size_of(T));
}

string_view :: inline (s: string, index: s64, count: s64 = -1) -> string {
    assert(index >= 0, "index = %", index);
    if count < 0 {
        c: string = ---;
        c.data    = s.data + index;
        c.count   = s.count - index;
        return c;
    }

    if index >= s.count  return "";

    if index + count > s.count {
        count = s.count - index;
    }

    c: string = ---;
    c.data    = s.data + index;
    c.count   = count;
    return c;
}

hsv_to_rgb :: (cx: float, cy: float, cz: float) -> (r: float, g: float, b: float) {
    cx /= 360.0;
    p: Vector3;
    p.x = abs(fract(cx + 1)     * 6 - 3) - 1;
    p.y = abs(fract(cx + 2/3.0) * 6 - 3) - 1;
    p.z = abs(fract(cx + 1/3.0) * 6 - 3) - 1;

    Clamp(*p.x, 0, 1);
    Clamp(*p.y, 0, 1);
    Clamp(*p.z, 0, 1);

    p.x = lerp(1, p.x, cy);
    p.y = lerp(1, p.y, cy);
    p.z = lerp(1, p.z, cy);
    
    return cz * p.x, cz * p.y, cz * p.z;
}

rgb_to_hsv :: (r: float, g: float, b: float) -> (h: float, s: float, v: float) {
    rgb_min := min(r, g, b);
    rgb_max := max(r, g, b);

    if rgb_max == 0  return 0, 0, 0;

    v := rgb_max;

    delta := rgb_max - rgb_min;
    
    s := delta / rgb_max;
    if s == 0 {  // This covers the case when rgb_max == rgb_min, so we don't worry about dividing by 0 below.
        return 0, 0, v;
    }

    h: float = ---;
    K :: (43/255.0);
    if rgb_max == r
        h = 0 + K * (g - b) / delta;
    else if rgb_max == g
        h = (85/255.0) + K * (b - r) / delta;
    else
        h = (171/255.0) + K * (r - g) / delta;

    return h*360, s, v;
}

fract :: inline (x: float) -> float { return x - floor(x); }

/// #no_debug breaks remedybg's line determination somehow (?)
do_debug_break :: () {
    debug_break();
}

Mem_Dump :: #type,distinct [] u8;
mem_dump_printer :: (builder: *String_Builder, any: Any, data: *void) -> handled: bool {
    if any.type != type_info(Mem_Dump) return false;

    data := << cast(*[] u8) any.value_pointer;
    mem_dump_to_builder(builder, data);
    return true;
}

Setup_Mem_Dump_Printer :: () #expand {
    old_struct_printer := context.print_style.struct_printer;
    `defer context.print_style.struct_printer = old_struct_printer;
    context.print_style.struct_printer = mem_dump_printer;
}

mem_dump_to_builder :: (builder: *String_Builder, data: [] u8) {
    old_default_format_int := context.print_style.default_format_int;
    defer context.print_style.default_format_int = old_default_format_int;
    context.print_style.default_format_int = FormatInt.{ base = 16, minimum_digits = 2 };

    leading_spaces := cast(s64) (cast(u64) data.data) % 16;
    start_addr := cast(* u8) (cast(u64) data.data) & 0xffff_ffff_ffff_fff0;

    print_to_builder(builder, "%: ", start_addr);
    for 0..(data.count + leading_spaces - 1) {
        if it < leading_spaces then
            append(builder, "  ");
        else
            print_to_builder(builder, "%", data[it - leading_spaces]);

        if (it + 1) % 16 == 0 && it + 1 != data.count + leading_spaces
            print_to_builder(builder, "\n%: ", start_addr + it + 1);
        else if (it + 1) % 4 == 0
            append(builder, " ");
    }
}

code_to_string :: (code: Code) -> string {
    #import "Program_Print";
    #import "Compiler";
    root := compiler_get_nodes(code);
    builder : String_Builder;
    builder.allocator = temporary_allocator;
    print_expression(*builder, root);
    return builder_to_string(*builder);
}

dbg_to_builder :: (builder: *String_Builder, code: Code) #expand {
    print_to_builder(builder, "% = %\n", #run code_to_string(code), #insert code);
}

log_dbg :: (code: Code) #expand {
    log("% = %\n", #run code_to_string(code), #insert code);
}

dbg :: (code: Code) #expand {
    print("% = %\n", #run code_to_string(code), #insert code);
}

// Constant structs don't work with compile time constructs yet, so we return
// all fields directly
get_expr_info :: (code: Code) -> kind: Code_Node.Kind, op_type: s32, full_expr: string, proc_expr: string, lhs: Code, rhs: Code {
    #import "Program_Print";

    root := compiler_get_nodes(code);

    builder: String_Builder;
    print_expression(*builder, root);
    full_expr := builder_to_string(*builder);

    if root.kind == {
        case .BINARY_OPERATOR;
            binop := cast(*Code_Binary_Operator) root;
            op_type := binop.operator_type;
            lhs := compiler_get_code(binop.left, code);
            rhs := compiler_get_code(binop.right, code);
            return xx root.kind, op_type, full_expr, "", lhs, rhs;

        case .PROCEDURE_CALL;
            proccall := cast(*Code_Procedure_Call) root;
            if proccall.arguments_sorted.count != 2 {
                dummy : Code = #code null;
                return xx root.kind, -1, full_expr, "", dummy, dummy;
            }

            builder: String_Builder;
            print_expression(*builder, proccall.procedure_expression);
            proc_expr := builder_to_string(*builder);

            lhs := compiler_get_code(proccall.arguments_sorted[0], code);
            rhs := compiler_get_code(proccall.arguments_sorted[1], code);
            return xx root.kind, -1, full_expr, proc_expr, lhs, rhs;

        case;

    }

    dummy : Code = #code null;
    return xx root.kind, -1, full_expr, "", dummy, dummy;
}

pretty_assert :: (code: Code, loc := #caller_location) #expand {
    if #insert code return;

    if context.handling_assertion_failure  return;  // Avoid infinite loops.
    context.handling_assertion_failure = true;

    kind, op_type, full_expr, proc_expr, lhs, rhs :: #run get_expr_info(code);

    message := "";

    #if kind == .BINARY_OPERATOR {
        builder : String_Builder;
        builder.allocator = temporary_allocator;

        print_to_builder(*builder, "(%) = (% ", full_expr, #insert lhs);

        if op_type < 128 {
            append(*builder, cast(u8) op_type);
        } else {
            append(*builder, operator_to_string(xx op_type));
        }

        print_to_builder(*builder, " %) = false", #insert rhs);
        message = builder_to_string(*builder, temporary_allocator);
    } else #if kind == .PROCEDURE_CALL {
        message = tprint("(%) = (%(%, %)) = false", full_expr, proc_expr, #insert lhs, #insert rhs);
    } else {
        message = tprint("(%) = false", full_expr);
    }

    // We provide 'loc' in case _STACK_TRACE is turned off, but assertion_failed may well
    // look at the stack trace if it is available.
    context.assertion_failed(loc, message);
    context.handling_assertion_failure = false;

} @NoProfile

#import "Basic";
#import "Math";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
GetRect :: #import "GetRect";
using Sock :: #import "Socket";
#import "System";
#import "Random";
#import "Compiler";
