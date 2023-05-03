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
        GetRect.label(r, tprint("mouse: %", mouse), *get_rect_theme.label_theme);

        sliders_rect = GetRect.get_rect(xx (window_width - 240), xx (window_height - 30), 200, 20);

        for * entities {
            {
                light_gray := Vector4.{ 0.6, 0.6, 0.6, 1.0 };
                Simp.set_shader_for_color();
                len := distance(mouse, it.pos);
                thick := 1.0;

                to_mouse := mouse - it.pos;
                to_mouse_rot := atan2(to_mouse.y, to_mouse.x);
                rot_m : Matrix2;
                rot_m.v[0] = .{  sin(to_mouse_rot), cos(to_mouse_rot) };
                rot_m.v[1] = .{ -cos(to_mouse_rot), sin(to_mouse_rot) };

                top_l := (mouse + it.pos) / 2 + multiply(rot_m, .{ -thick, -len / 2 });
                bot_l := (mouse + it.pos) / 2 + multiply(rot_m, .{ -thick, +len / 2 });
                top_r := (mouse + it.pos) / 2 + multiply(rot_m, .{ +thick, -len / 2 });
                bot_r := (mouse + it.pos) / 2 + multiply(rot_m, .{ +thick, +len / 2 });

                Simp.immediate_quad(
                    top_l, bot_l, bot_r, top_r,
                    light_gray, light_gray, light_gray, light_gray,
                );
            }

            to_mouse := mouse - it.pos;
            to_rot := atan2(to_mouse.y, to_mouse.x);

            GetRect.slider(sliders_rect, *to_rot, -PI, PI, PI / 9, *get_rect_theme.slider_theme, "to_rot ");

            // TODO: this should take into account cases when atan2 changes sign
            // -pi |+------0--*>---|+ pi
            rot_delta := clamp(to_rot - it.rot, -ROT_SPEED, ROT_SPEED);

            sliders_rect.y -= 20;
            GetRect.slider(sliders_rect, *rot_delta, -ROT_SPEED, ROT_SPEED, PI / 9, *get_rect_theme.slider_theme, "delta clamped ");

            it.rot = it.rot + rot_delta;
            while it.rot > +PI  it.rot -= 2 * PI;
            while it.rot < -PI  it.rot += 2 * PI;

            sliders_rect.y -= 20;
            GetRect.slider(sliders_rect, *it.rot, -PI, PI, PI / 9, *get_rect_theme.slider_theme, "rot ");

            rot_m : Matrix2;
            rot_m.v[0] = .{  sin(it.rot), cos(it.rot) };
            rot_m.v[1] = .{ -cos(it.rot), sin(it.rot) };

            /////////////////////////////////////////////////////////////////////////////////
            // Draw it
            Simp.set_shader_for_color();

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
