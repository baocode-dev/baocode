#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "clipboard.h"
#include "login_window.h"
#include "flutter/generated_plugin_registrant.h"

#include <gdk/gdkkeysyms.h>
#include <string.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkWidget* view;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Same client size and minimum as the Windows runner (docs/windows.md).
static const int kDefaultWidth = 1024;
static const int kDefaultHeight = 760;
static const int kMinWidth = 400;
static const int kMinHeight = 540;

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static const char* map_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean map_bool(FlValue* args, const char* key, gboolean fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

// GTK file chooser. Returned names are owned by the list (g_free each).
static GSList* choose_files(GtkWindow* parent, GtkFileChooserAction action,
                             const char* title, gboolean multiple,
                             const char* folder, const char* name,
                             gboolean overwrite) {
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      title, parent, action, "Cancel", GTK_RESPONSE_CANCEL,
      action == GTK_FILE_CHOOSER_ACTION_SAVE ? "Save" : "Open",
      GTK_RESPONSE_ACCEPT, nullptr);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  if (action != GTK_FILE_CHOOSER_ACTION_SAVE) {
    gtk_file_chooser_set_select_multiple(chooser, multiple);
  }
  if (overwrite) {
    gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  }
  if (folder != nullptr && folder[0] != '\0') {
    gtk_file_chooser_set_current_folder(chooser, folder);
  }
  if (name != nullptr && name[0] != '\0') {
    gtk_file_chooser_set_current_name(chooser, name);
  }
  GSList* names = nullptr;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    if (multiple) {
      names = gtk_file_chooser_get_filenames(chooser);
    } else {
      char* filename = gtk_file_chooser_get_filename(chooser);
      if (filename != nullptr) {
        names = g_slist_append(names, filename);
      }
    }
  }
  gtk_widget_destroy(dialog);
  return names;
}

static void free_filenames(GSList* names) {
  g_slist_free_full(names, g_free);
}

static FlValue* filenames_as_strings(GSList* names) {
  FlValue* list = fl_value_new_list();
  for (GSList* item = names; item != nullptr; item = item->next) {
    fl_value_append_take(list, fl_value_new_string((const char*)item->data));
  }
  return list;
}

// What FileDrops.decode reads: {path, directory} each.
static FlValue* filenames_as_file_maps(GSList* names) {
  FlValue* list = fl_value_new_list();
  for (GSList* item = names; item != nullptr; item = item->next) {
    const char* path = (const char*)item->data;
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "path", fl_value_new_string(path));
    fl_value_set_string_take(
        map, "directory",
        fl_value_new_bool(g_file_test(path, G_FILE_TEST_IS_DIR)));
    fl_value_append_take(list, map);
  }
  return list;
}

static double map_number(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return 0;
}

static const char* value_string(FlValue* map, const char* key) {
  return map_string(map, key);
}

struct MenuPick {
  gchar* id;
  GMainLoop* loop;
};

static void menu_item_activated(GtkMenuItem* item, gpointer user_data) {
  MenuPick* pick = static_cast<MenuPick*>(user_data);
  const gchar* id =
      static_cast<const gchar*>(g_object_get_data(G_OBJECT(item), "id"));
  // Wayland allows the clipboard read here, inside the paste action, and
  // not later when Dart asks.
  if (id != nullptr && strcmp(id, "paste") == 0) clipboard_snapshot();
  g_free(pick->id);
  pick->id = g_strdup(id);
}

static void menu_deactivated(GtkMenuShell* menu, gpointer user_data) {
  MenuPick* pick = static_cast<MenuPick*>(user_data);
  if (g_main_loop_is_running(pick->loop)) g_main_loop_quit(pick->loop);
}

// The system's menu. Returns the chosen id, or null when dismissed. The
// caller frees it.
static gchar* show_context_menu(MyApplication* self, double x, double y,
                                 FlValue* items) {
  GtkWidget* menu = gtk_menu_new();
  if (self->view != nullptr) {
    gtk_menu_attach_to_widget(GTK_MENU(menu), self->view, nullptr);
  }
  MenuPick pick = {nullptr, g_main_loop_new(nullptr, FALSE)};
  if (items != nullptr && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    const size_t count = fl_value_get_length(items);
    for (size_t i = 0; i < count; i++) {
      FlValue* item = fl_value_get_list_value(items, i);
      if (item == nullptr || fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
        continue;
      }
      FlValue* separator = fl_value_lookup_string(item, "separator");
      GtkWidget* row;
      if (separator != nullptr &&
          fl_value_get_type(separator) == FL_VALUE_TYPE_BOOL &&
          fl_value_get_bool(separator)) {
        row = gtk_separator_menu_item_new();
      } else {
        const char* label = value_string(item, "label");
        row = gtk_menu_item_new_with_label(label == nullptr ? "" : label);
        const char* id = value_string(item, "id");
        if (id != nullptr) {
          g_object_set_data_full(G_OBJECT(row), "id", g_strdup(id), g_free);
        }
        FlValue* enabled = fl_value_lookup_string(item, "enabled");
        if (enabled != nullptr &&
            fl_value_get_type(enabled) == FL_VALUE_TYPE_BOOL &&
            !fl_value_get_bool(enabled)) {
          gtk_widget_set_sensitive(row, FALSE);
        }
        g_signal_connect(row, "activate", G_CALLBACK(menu_item_activated),
                         &pick);
      }
      gtk_menu_shell_append(GTK_MENU_SHELL(menu), row);
    }
  }
  gtk_widget_show_all(menu);
  g_signal_connect(menu, "deactivate", G_CALLBACK(menu_deactivated), &pick);

  GdkWindow* gdk =
      self->view == nullptr ? nullptr : gtk_widget_get_window(self->view);
  if (gdk != nullptr) {
    const int scale = gtk_widget_get_scale_factor(self->view);
    GdkRectangle rect = {};
    rect.x = static_cast<int>(x * scale + (x < 0 ? -0.5 : 0.5));
    rect.y = static_cast<int>(y * scale + (y < 0 ? -0.5 : 0.5));
    rect.width = 1;
    rect.height = 1;
    gtk_menu_popup_at_rect(GTK_MENU(menu), gdk, &rect, GDK_GRAVITY_NORTH_WEST,
                           GDK_GRAVITY_NORTH_WEST, nullptr);
  } else {
    gtk_menu_popup_at_pointer(GTK_MENU(menu), nullptr);
  }
  g_main_loop_run(pick.loop);
  g_main_loop_unref(pick.loop);
  gtk_widget_destroy(menu);
  return pick.id;
}

static gboolean on_key_press(GtkWidget* widget, GdkEventKey* event,
                             gpointer user_data) {
  (void)widget;
  (void)user_data;
  const guint key = event->keyval;
  const gboolean ctrl = (event->state & GDK_CONTROL_MASK) != 0;
  const gboolean shift = (event->state & GDK_SHIFT_MASK) != 0;
  const gboolean paste = (ctrl && (key == GDK_KEY_v || key == GDK_KEY_V)) ||
                         (shift && key == GDK_KEY_Insert);
  if (paste) clipboard_snapshot();
  return FALSE;
}

static void reveal_path(const char* path) {
  if (path == nullptr || path[0] == '\0') return;
  g_autofree char* target = g_file_test(path, G_FILE_TEST_IS_DIR)
                                ? g_strdup(path)
                                : g_path_get_dirname(path);
  char* argv[] = {(char*)"xdg-open", target, nullptr};
  g_spawn_async(nullptr, argv, nullptr, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
                nullptr, nullptr);
}

// baocode/window: the calls WindowControls makes when this host is a desktop.
// Menus, clipboard images and drag-out stay unimplemented (MissingPlugin);
// the app already treats those as optional.
static void window_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const char* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(name, "pickDirectory") == 0) {
    GSList* names = choose_files(self->window, GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
                                 "Open Folder", FALSE, nullptr, nullptr, FALSE);
    g_autoptr(FlValue) result = nullptr;
    if (names != nullptr) {
      result = fl_value_new_string((const char*)names->data);
    }
    free_filenames(names);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "pickFiles") == 0) {
    GSList* names =
        choose_files(self->window, GTK_FILE_CHOOSER_ACTION_OPEN, "Open", TRUE,
                     nullptr, nullptr, FALSE);
    g_autoptr(FlValue) result = filenames_as_file_maps(names);
    free_filenames(names);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "pickOpenFiles") == 0) {
    GSList* names = choose_files(
        self->window, GTK_FILE_CHOOSER_ACTION_OPEN, "Open File",
        map_bool(args, "multiple", TRUE), map_string(args, "directory"),
        nullptr, FALSE);
    g_autoptr(FlValue) result = filenames_as_strings(names);
    free_filenames(names);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "pickSaveFile") == 0) {
    GSList* names = choose_files(
        self->window, GTK_FILE_CHOOSER_ACTION_SAVE, "Save", FALSE,
        map_string(args, "directory"), map_string(args, "name"), TRUE);
    g_autoptr(FlValue) result = nullptr;
    if (names != nullptr) {
      result = fl_value_new_string((const char*)names->data);
    }
    free_filenames(names);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "revealInFinder") == 0) {
    const char* path = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      path = fl_value_get_string(args);
    }
    reveal_path(path);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(name, "readPasteboardText") == 0) {
    g_autoptr(FlValue) result = clipboard_text_value();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "readPasteboardFiles") == 0) {
    g_autoptr(FlValue) result = clipboard_files_value();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "readPasteboardImages") == 0) {
    g_autoptr(FlValue) result = clipboard_images_value();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "readImageFile") == 0) {
    const char* path = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      path = fl_value_get_string(args);
    }
    g_autoptr(FlValue) result = clipboard_image_file_value(path);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "toggleFullScreen") == 0) {
    // Answered with whether it is going to be (the window manager's to do).
    GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->window));
    const gboolean full_screen =
        gdk_window != nullptr &&
        (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    if (full_screen) {
      gtk_window_unfullscreen(self->window);
    } else {
      gtk_window_fullscreen(self->window);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(!full_screen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(name, "showContextMenu") == 0) {
    FlValue* items = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      items = fl_value_lookup_string(args, "items");
    }
    g_autofree gchar* chosen = show_context_menu(
        self, map_number(args, "x"), map_number(args, "y"), items);
    g_autoptr(FlValue) result =
        chosen == nullptr ? nullptr : fl_value_new_string(chosen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

static void register_window_channel(MyApplication* self, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_clear_object(&self->window_channel);
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "baocode/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                             window_method_call_cb, self,
                                             nullptr);
  // The channel build's login window (see lib/channel/account/).
  login_window_register(fl_engine_get_binary_messenger(engine), self->window);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window), (gpointer*)&self->window);

  // The app paints its own header on Windows only. Everywhere else the
  // system draws the caption, so this is a normal title bar (no GTK
  // header bar stacked on top of the Flutter view).
  gtk_window_set_title(window, "BaoCode");
  gtk_window_set_default_size(window, kDefaultWidth, kDefaultHeight);
  GdkGeometry geometry = {};
  geometry.min_width = kMinWidth;
  geometry.min_height = kMinHeight;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = GTK_WIDGET(view);
  g_object_add_weak_pointer(G_OBJECT(view), (gpointer*)&self->view);
  g_signal_connect(view, "key-press-event", G_CALLBACK(on_key_press), self);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_window_channel(self, view);

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
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
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

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
