main :: () {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // parse command line arguments
    args := get_command_line_arguments();
    am_server := true;
    connecting := true;
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
    server_addr : *addrinfo;
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
        wave_spawner.waves = array_view(all_circle_waves, 0, all_circle_waves.count / 2),
    };
    entities[1] = .{
        pos = .{ window_width / 2.0 + 100, window_height / 2.0 },
        rot = 0,
        size = .{ 10, 20 },
        collision_radius = 15,
        color = .{ 0, 0, 1, 1 },
        wave_color = .{ 0.1, 0.4, 0.8, 1.0 },
        wave_spawner.waves = array_view(all_circle_waves, all_circle_waves.count / 2, all_circle_waves.count / 2),
    };
    assert(entities.count == 2, "TODO");

    coin_spawner = .{ coins = coin_buffer };

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
        my_index : int;
        their_index : int;
        if am_server {
            my_index = 0; their_index = 1;
        } else {
            my_index = 1; their_index = 0;
        }
        mouses[my_index] = mouse;
        if remote_data_received {
            mouses[their_index] = last_received.mouse;
        } else {
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

        next_to_send.mouse = mouses[my_index];
        next_to_send.entity = entities[my_index];

        if remote_data_received {
            // Override the data we just simulated
            entities[their_index] = last_received.entity;
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Update circle waves

        for * all_circle_waves {
            if !it.is_enabled continue;

            it.outer_radius += RADIUS_DELTA;
            if it.outer_radius > MAX_RADIUS {
                it.is_enabled = false;
            }

            it.color.w *= FADE_AWAY_FACTOR;
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

            for * wave: all_circle_waves {
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

                // TODO: decouple force from color
                wave_force := WAVE_STRENGTH * wave.color.w * sin(tangentality_to_wave);

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

                Simp.immediate_quad(
                    top_l, top_r, bot_r, bot_l,
                    color, color, color, color,
                );
            }

            // Draw strong ones first so that weak ones are drawn correctly over
            for k: 0..N-1 for * all_circle_waves {
                draw_circle_wave(draw_weak_ones = false);
            }

            for k: 0..N-1 for * all_circle_waves {
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

        send_pending_packet :: (disconnected: *bool) -> fully_sent := false {
            data := (cast(*u8) *partially_sent.data) + partially_sent.size;
            size := packet_size - partially_sent.size;
            rc := send(conn_sock, data, xx size, 0);
            if rc < 0 {
                err := get_last_socket_error();
                if err != SOCKET_WOULDBLOCK  {
                    log_error("Failed sending to socket: #% %", err, get_error_string(err));
                    #if OS == .WINDOWS {
                        disconnected.* = (err == WSAECONNRESET);
                    }
                }
                return;
            }

            partially_sent.size += xx rc;
            if partially_sent.size == packet_size {
                // fully sent
                partially_sent.size = 0;
                partially_sent.data = next_to_send;
                return fully_sent = true;
            }

            return;
        }

        // FIXME: copypaste
        receive_pending_packet :: (disconnected: *bool) {
            data := (cast(*u8) *partially_received.data) + partially_received.size;
            size := packet_size - partially_received.size;
            rc := recv(conn_sock, data, xx size, 0);
            if rc < 0 {
                err := get_last_socket_error();
                if err != SOCKET_WOULDBLOCK  {
                    log_error("Failed receiving from socket: #% %", err, get_error_string(err));
                    #if OS == .WINDOWS {
                        disconnected.* = (err == WSAECONNRESET);
                    }
                }
                return;
            }

            partially_received.size += xx rc;
            if partially_received.size == packet_size {
                // fully received
                partially_received.size = 0;
                last_received = partially_received.data;
                remote_data_received = true;
            }
        }

        remote_data_received = false;

        if !connecting {
            time := get_time();
            disconnected := false;

            if partially_sent.size {
                if send_pending_packet(*disconnected)
                    last_packet_sent_time = time;
            }
            // Maybe sent the last pending packet, try sending the new one
            if !partially_sent.size {
                if time > last_packet_sent_time + 1 / cast(float) packets_sent_per_second
                    if send_pending_packet(*disconnected)
                        last_packet_sent_time = time;
            }

            // TODO: read all pending packets
            if  partially_received.size  receive_pending_packet(*disconnected);
            // Maybe received the last packet, try receiving another one
            if !partially_received.size  receive_pending_packet(*disconnected);
            if disconnected {
                if am_server {
                    log_error("lost connection to client, will listen for more connections...");
                } else /* am_client */ {
                    log_error("lost connection to server, will retry connecting...");
                    // TODO: the socket should be closed and reinitialized

                }
                connecting = true;
            }
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // End of frame
        reset_temporary_storage();

        time_end := get_time();
        millis_spent_on_frame := 1000 * (time_end - time_start);
        millis_expected_to_spend := 1000 / 60;
        millis_left_to_sleep := millis_expected_to_spend - millis_spent_on_frame;
        if millis_left_to_sleep > 0 {
            // log("going to sleep for %", millis_left_to_sleep, flags = .VERY_VERBOSE_ONLY);
            sleep_milliseconds(xx millis_left_to_sleep);
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

red_ship_id :: 0;
blue_ship_id :: 1;
mouses : [entities.count] Vector2;

Entity :: struct {
    pos: Vector2;
    rot: f32;
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
    origin: Vector2;
    outer_radius: f32;
    color: Vector4;
    width: f32;
    is_enabled: bool = false;
};

circle_wave :: inline (origin: Vector2, color: Vector4, is_enabled: bool = true) -> CircleWave {
    return .{
        origin = origin,
        is_enabled = is_enabled,
        outer_radius = INITIAL_OUTER_RADIUS,
        color = color,
        width = WAVE_WIDTH,
    };
}

N_CIRCLE_WAVES :: 1024;
all_circle_waves : [N_CIRCLE_WAVES] CircleWave;

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
    origin: Vector2;
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
conn_sock : Socket;
listen_sock : Socket;

packets_sent_per_second := 30;
last_packet_sent_time : f64 = 0.0;

partially_sent     : Network_Packet_Piece;
next_to_send       : Network_Packet;
partially_received : Network_Packet_Piece;
last_received      : Network_Packet;

remote_data_received : bool;

packet_size :: size_of(Network_Packet);
Network_Packet :: struct {
    header : [8] u8 = xx "packet[[";
    mouse: Vector2;
    entity: Entity;
    footer : [8] u8 = xx "]]tekcap";
}
Network_Packet_Piece :: struct {
    data: Network_Packet;
    size: s32;
}

f32 :: float32;
f64 :: float64;

array_equals :: (lhs: [$N] $T, rhs: [N] T) -> bool {
    for lhs {
        if rhs[it_index] != it return false;
    }
    return true;
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

#import "Basic";
#import "Math";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
GetRect :: #import "GetRect";
using Sock :: #import "Socket";
#import "System";
#import "Random";
