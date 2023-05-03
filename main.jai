main :: () {
    window_width  : s32 = 860;
    window_height : s32 = 480;
    window := create_window(window_width, window_height, "jg");
    quit := false;

    Simp.set_render_target(window);
    GetRect.ui_init();

    entities[0] = .{
        pos = .{ window_width / 2.0, window_height / 2.0 },
        rot = 0,
        size = .{ 10, 20 },
        color = .{ 1, 0, 0, 1 },
    };
    assert(entities.count == 1, "TODO");

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

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            GetRect.getrect_handle_event(it);

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }
            }
        }

        mouse : Vector2;
        {
            x, y, ok := get_mouse_pointer_position(window, true);
            if ok {
                mouse.x = xx x;
                mouse.y = xx y;
            }
        }

        GetRect.ui_per_frame_update(window, window_width, window_height, time);
        get_rect_theme := GetRect.default_theme_procs[GetRect.Default_Themes.Default]();
        GetRect.set_default_theme(get_rect_theme);
        r : GetRect.Rect;

        ////////////////////////////////////////////////////////////////
        // Update
        for * entities {
            it.rot += ROT_SPEED;
        }

        ////////////////////////////////////////////////////////////////
        // Draw
        Simp.update_window (window);
        Simp.clear_render_target (0.1, 0.1, 0.1, 1);

        Simp.set_shader_for_color();

        r = GetRect.get_rect(10, xx (window_height - 40), 200, 20);
        GetRect.label(r, tprint("mouse: %", mouse), *get_rect_theme.label_theme);

        for * entities {
            using it;

            {
                light_gray := Vector4.{ 0.6, 0.6, 0.6, 1.0 };
                Simp.set_shader_for_color();
                len := distance(mouse, pos);
                thick := 1.0;

                to_mouse := mouse - pos;
                to_mouse_rot := atan2(to_mouse.y, to_mouse.x);
                rot_m : Matrix2;
                rot_m.v[0] = .{  sin(to_mouse_rot), cos(to_mouse_rot) };
                rot_m.v[1] = .{ -cos(to_mouse_rot), sin(to_mouse_rot) };

                top_l := (mouse + pos) / 2 + multiply(rot_m, .{ -thick, -len / 2 });
                bot_l := (mouse + pos) / 2 + multiply(rot_m, .{ -thick, +len / 2 });
                top_r := (mouse + pos) / 2 + multiply(rot_m, .{ +thick, -len / 2 });
                bot_r := (mouse + pos) / 2 + multiply(rot_m, .{ +thick, +len / 2 });

                Simp.immediate_quad(
                    top_l, bot_l, bot_r, top_r,
                    light_gray, light_gray, light_gray, light_gray,
                );
            }

            to_mouse := mouse - pos;
            to_rot := atan2(to_mouse.y, to_mouse.x);
            // TODO: this should take into account cases when atan2 changes sign
            // -pi |+------0--*>---|+ pi
            rot_delta := to_rot - rot;
            if rot_delta > ROT_SPEED rot_delta = ROT_SPEED;
            // TODO: this is wrong and I'm too stupid to figure out why
            //
            // if rot_delta < -ROT_SPEED rot_delta = -ROT_SPEED;
            // rot_delta := clamp(to_rot - rot, -ROT_SPEED, ROT_SPEED);
            rot = rot + rot_delta;
            // if rot > +PI  rot = fmod_cycling(rot + PI, 2*PI) - PI;
            // if rot < -PI  rot = fmod_cycling(rot - PI, 2*PI) + PI;

            r.y -= 20;
            GetRect.label(r,
                tprint("[%] to_rot: %", it_index, to_rot),
                *get_rect_theme.label_theme);

            r.y -= 20;
            GetRect.label(r,
                tprint("[%] rot: %, delta: %", it_index, rot, rot_delta),
                *get_rect_theme.label_theme);


            rot_m : Matrix2;
            rot_m.v[0] = .{  sin(rot), cos(rot) };
            rot_m.v[1] = .{ -cos(rot), sin(rot) };

            top_l := pos + multiply(rot_m, .{ - it.size.x / 2, - it.size.y / 2 });
            top_r := pos + multiply(rot_m, .{ - it.size.x / 2, + it.size.y / 2 });
            bot_l := pos + multiply(rot_m, .{ + it.size.x / 2, + it.size.y / 2 });
            bot_r := pos + multiply(rot_m, .{ + it.size.x / 2, - it.size.y / 2 });

            Simp.set_shader_for_color();
            Simp.immediate_quad(
                top_l, top_r, bot_l, bot_r,
                it.color, it.color, it.color, it.color,
            );

        }

        r = GetRect.get_rect(10, xx (window_height - 20), 200, 20);
        GetRect.slider(r, *ROT_SPEED, 0.0, 0.1, 0.005, *get_rect_theme.slider_theme, "ROT_SPEED ");

        Simp.swap_buffers(window);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

ROT_SPEED := .03;
MOV_SPEED := 1;

N_ENTITIES :: 1;
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
