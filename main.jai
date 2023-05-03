main :: () {
    args := get_command_line_arguments();
    if args.count < 2 {
        log_error("expected a command 'client' or 'server'");
        exit(1);
    }
    am_server := false;
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

    port : u16 = 2276;
    socket_init();
    conn_sock : Socket;
    if am_server {
        listen_sock := socket(AF_INET, .SOCK_STREAM, .TCP);
        if listen_sock == INVALID_SOCKET {
            log_error("Failed creating a socket: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        rc := bind(listen_sock, 0, port, AF_INET);
        if rc {
            log_error("`bind` failed on port %: %", port, get_error_string(get_last_socket_error()));
            exit(1);
        }

        rc = listen(listen_sock, SOMAXCONN);
        if rc {
            log_error("`listen` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        conn_sock = accept(listen_sock, null, null);
        if conn_sock == INVALID_SOCKET {
            log_error("`accept` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }
    } else {
        addr : *addrinfo;
        hints := addrinfo.{ ai_family = AF_INET, ai_socktype = .SOCK_STREAM, ai_protocol = .TCP };
        rc := getaddrinfo(to_c_string(server_address), tprint("%\0", port).data, *hints, *addr);
        if rc {
            log_error("`getaddrinfo` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        conn_sock = socket(addr.ai_family, addr.ai_socktype, addr.ai_protocol);
        if conn_sock == INVALID_SOCKET {
            log_error("Failed creating a socket: %", get_error_string(get_last_socket_error()));
            exit(1);
        }

        rc = connect(conn_sock, addr.ai_addr, xx addr.ai_addrlen);
        if rc {
            log_error("`connect` failed: %", get_error_string(get_last_socket_error()));
            exit(1);
        }
    }

    window_width  : s32 = 860;
    window_height : s32 = 480;
    window := create_window(window_width, window_height, "jg");
    quit := false;

    Simp.set_render_target(window);
    GetRect.ui_init();

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

    while !quit {
        time := get_time();
        ////////////////////////////////////////////////////////////////
        // Input
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == window {
                window_width  = it.width;
                window_height = it.height;
            }
        }

        buf : [size_of(Entity)] u8;

        send_entity :: (conn_sock: Socket, entity: *Entity) -> quit := false {
            buf : [size_of(Entity)] u8;
            << cast(*Entity) buf.data = << entity;
            n_bytes_sent := 0;
            while n_bytes_sent != buf.count {
                rc := send(conn_sock, buf.data + n_bytes_sent, xx (buf.count - n_bytes_sent), 0);
                if rc < 0 {
                    err := get_last_socket_error();
                    log_error("Failed sending to socket: %", get_error_string(err));
                    return quit = true;
                }
                n_bytes_sent += rc;
            }
            return;
        }

        recv_entity :: (conn_sock: Socket, entity: *Entity) -> quit := false {
            buf : [size_of(Entity)] u8;
            n_bytes_read := 0;
            while n_bytes_read != buf.count {
                rc := recv(conn_sock, buf.data + n_bytes_read, xx (buf.count - n_bytes_read), 0);
                if rc < 0 {
                    err := get_last_socket_error();
                    log_error("Failed receiving from socket: %", get_error_string(err));
                    return quit = true;
                }
                n_bytes_read += rc;
            }
            << entity = << cast(*Entity) buf.data;
            return;
        }

        if am_server {
            quit = send_entity(conn_sock, *entities[0]);
            quit = recv_entity(conn_sock, *entities[1]);
        } else {
            quit = recv_entity(conn_sock, *entities[0]);
            quit = send_entity(conn_sock, *entities[1]);
        }

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

        GetRect.ui_per_frame_update(window, window_width, window_height, time);
        get_rect_theme := GetRect.default_theme_procs[GetRect.Default_Themes.Default]();
        GetRect.set_default_theme(get_rect_theme);
        r : GetRect.Rect;
        sliders_rect : GetRect.Rect;

        ////////////////////////////////////////////////////////////////
        // Update/Draw
        Simp.update_window (window);
        Simp.clear_render_target (0.1, 0.1, 0.1, 1);

        Simp.set_shader_for_color();

        r = GetRect.get_rect(10, xx (window_height - 40), 200, 20);
        // GetRect.label(r, tprint("mouse: %", mouse), *get_rect_theme.label_theme);

        sliders_rect = GetRect.get_rect(xx (window_width - 240), xx (window_height - 30), 200, 20);

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

        // Update
        it : *Entity;
        if am_server {
            it = *entities[0];
        } else {
            it = *entities[1];
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

        for * entities {
            /////////////////////////////////////////////////////////////////////////////////
            // Draw it
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

            /////////////////////////////////////////////////////////////////////////////////
        }

        r = GetRect.get_rect(10, xx (window_height - 20), 200, 20);
        GetRect.slider(r, *ROT_SPEED, 0.0, 0.1, 0.005, *get_rect_theme.slider_theme, "ROT_SPEED ");
        r.y -= 20;

        GetRect.slider(r, *MOV_SPEED, 0.0, 10, 0.5, *get_rect_theme.slider_theme, "MOV_SPEED ");
        r.y -= 20;

        Simp.swap_buffers(window);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

ARROW : struct {
    OFS := .21;
    LEN := .88;
    SPAN := 1.69;
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

f32 :: float32;
f64 :: float64;

#import "Basic";
#import "Math";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
GetRect :: #import "GetRect";
using Sock :: #import "Socket";
#import "System";
