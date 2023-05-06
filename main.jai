main :: () {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // parse command line arguments
    args := get_command_line_arguments();
    if args.count < 2 {
        log_error("expected a command 'client' or 'server'");
        exit(1);
    }
    am_server := false;
    connecting := true;
    server_address : string;
    if args[1] == {
        case "server";
            am_server = true;

        case "client";
            if args.count < 3 {
                log_error("expected a server address");
                exit(1);
            }
            server_address = args[2];

        case;
            log_error("expected a command 'client' or 'server'");
            exit(1);
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
        color = .{ 1, 0, 0, 1 },
    };
    entities[1] = .{
        pos = .{ window_width / 2.0 + 100, window_height / 2.0 },
        rot = 0,
        size = .{ 10, 20 },
        color = .{ 0, 0, 1, 1 },
    };
    assert(entities.count == 2, "TODO");

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
                    debug_break();
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
        it : *Entity;
        adversary : *Entity;
        if am_server {
            it = *entities[0];
            adversary = *entities[1];
        } else {
            it = *entities[1];
            adversary = *entities[0];
        }
        to_mouse := mouse - it.pos;
        to_rot := atan2(to_mouse.y, to_mouse.x);

        GetRect.slider(sliders_rect, *to_rot, -PI, PI, PI / 9, *get_rect_theme.slider_theme, "to_rot ");
        sliders_rect.y -= 20;

        rot_delta := to_rot - it.rot;
        if rot_delta > PI || rot_delta < -PI rot_delta = -rot_delta;
        rot_delta = clamp(rot_delta, -ROT_SPEED, ROT_SPEED);

        GetRect.slider(sliders_rect, *rot_delta, -ROT_SPEED, ROT_SPEED, PI / 9, *get_rect_theme.slider_theme, "delta clamped ");
        sliders_rect.y -= 20;

        it.rot = it.rot + rot_delta;
        while it.rot > +PI  it.rot -= 2 * PI;
        while it.rot < -PI  it.rot += 2 * PI;

        GetRect.slider(sliders_rect, *it.rot, -PI, PI, PI / 9, *get_rect_theme.slider_theme, "rot ");
        sliders_rect.y -= 20;

        rot_m : Matrix2;
        rot_m.v[0] = .{  sin(it.rot), cos(it.rot) };
        rot_m.v[1] = .{ -cos(it.rot), sin(it.rot) };

        it.pos += MOV_SPEED * multiply(rot_m, .{ 0, 1 });

        next_to_send.mouse = mouse;
        next_to_send.entity = << it;

        << adversary = last_received.entity;
        adversary_mouse := last_received.mouse;

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Draw
        Simp.set_shader_for_color();
        Simp.immediate_quad(
            adversary_mouse + .{ -ADVERSARY_MOUSE.size / 2, -ADVERSARY_MOUSE.size / 2 },
            adversary_mouse + .{ -ADVERSARY_MOUSE.size / 2, +ADVERSARY_MOUSE.size / 2 },
            adversary_mouse + .{ +ADVERSARY_MOUSE.size / 2, +ADVERSARY_MOUSE.size / 2 },
            adversary_mouse + .{ +ADVERSARY_MOUSE.size / 2, -ADVERSARY_MOUSE.size / 2 },
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

        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // Global variables debug editing
        r := GetRect.get_rect(10, xx (window_height - 20), 200, 20);
        GetRect.slider(r, *ROT_SPEED, 0.0, 0.1, 0.005, *get_rect_theme.slider_theme, "ROT_SPEED ");

        r.y -= 20;
        GetRect.slider(r, *MOV_SPEED, 0.0, 10, 0.5, *get_rect_theme.slider_theme, "MOV_SPEED ");

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
                        #if OS == .WINDOWS {
                            // XXX: am I doing something wrong, or why would we get here?
                            if err == WSAEISCONN  connecting = false;
                        }
                        if connecting  log_error("`connect` failed: #% %", err, get_error_string(err));
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
                        <<disconnected = (err == WSAECONNRESET);
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
                        <<disconnected = (err == WSAECONNRESET);
                    }
                }
                return;
            }

            partially_received.size += xx rc;
            if partially_received.size == packet_size {
                // fully received
                partially_received.size = 0;
                last_received = partially_received.data;
            }
        }

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

ROT_SPEED := .03;
MOV_SPEED := 1.0;

N_ENTITIES :: 2;
entities : [N_ENTITIES] Entity;

Entity :: struct {
    pos: Vector2;
    rot: f32;
    size: Vector2;
    color: Vector4;
};

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

#import "Basic";
#import "Math";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
GetRect :: #import "GetRect";
using Sock :: #import "Socket";
#import "System";
