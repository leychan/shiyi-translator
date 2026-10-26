#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifndef NDEBUG
#include <cstdint>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

#ifndef NDEBUG
// Inspect GTK + Flutter composition in desktop tests, beyond Flutter's own
// transparent screenshot. This diagnostic channel is absent in release builds.
static void inspect_surface(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(call), "inspectSurface") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  GtkWidget* window = GTK_WIDGET(data);
  const int width = gtk_widget_get_allocated_width(window);
  const int height = gtk_widget_get_allocated_height(window);
  cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
  cairo_t* context = cairo_create(surface);
  gtk_widget_draw(window, context);
  cairo_destroy(context);
  cairo_surface_flush(surface);
  unsigned char* pixels = cairo_image_surface_get_data(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  g_autoptr(FlValue) response = fl_value_new_map();
  g_autoptr(FlValue) corners = fl_value_new_list();
  const int points[4][2] = {{0, 0}, {width - 1, 0}, {0, height - 1}, {width - 1, height - 1}};
  for (const auto& point : points) {
    const auto pixel = *reinterpret_cast<const uint32_t*>(pixels + point[1] * stride + point[0] * 4);
    fl_value_append_take(corners, fl_value_new_int(pixel >> 24));
  }
  const auto center = *reinterpret_cast<const uint32_t*>(pixels + (height / 2) * stride + (width / 2) * 4);
  fl_value_set_string(response, "cornerAlpha", corners);
  fl_value_set_string_take(response, "centerAlpha", fl_value_new_int(center >> 24));
  fl_value_set_string_take(response, "visualDepth", fl_value_new_int(gdk_visual_get_depth(gtk_widget_get_visual(window))));
  cairo_surface_destroy(surface);
  fl_method_call_respond_success(call, response, nullptr);
}
#endif

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Flutter draws the rounded outline. Preserve its alpha all the way through
  // GTK to the desktop compositor instead of filling the corners with black.
  GdkScreen* window_screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(window_screen);
  if (rgba_visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  g_autoptr(GtkCssProvider) transparent_style = gtk_css_provider_new();
  gtk_css_provider_load_from_data(transparent_style,
      "window { background-color: transparent; background-image: none; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(GTK_WIDGET(window)),
      GTK_STYLE_PROVIDER(transparent_style), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "拾译 · Shiyi Translator");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "拾译 · Shiyi Translator");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // window_manager's background setting only affects GTK; FlView also needs
  // an alpha-zero clear color. Opaque Flutter pages still paint normally.
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Dart/window_manager owns presentation. In particular, a cold --selection
  // launch must keep the management window hidden while opening the popup.
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

#ifndef NDEBUG
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* diagnostics = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "dev.justtranslator/window-diagnostics", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(diagnostics, inspect_surface, window, nullptr);
  g_object_set_data_full(G_OBJECT(view), "window-diagnostics", diagnostics, g_object_unref);
#endif

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("拾译 · Shiyi Translator");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
