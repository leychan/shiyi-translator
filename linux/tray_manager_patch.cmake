# tray_manager 0.5.3 的 destroy 只隐藏图标，会让重试复用连接失败的对象。
# 在构建目录生成修正版，保留依赖缓存原样；上游实现变化时明确报错。
get_target_property(tray_sources tray_manager_plugin SOURCES)
get_target_property(tray_source_dir tray_manager_plugin SOURCE_DIR)
set(tray_source "${tray_source_dir}/tray_manager_plugin.cc")
file(READ "${tray_source}" tray_code)
set(old_destroy "    app_indicator_set_status(indicator, APP_INDICATOR_STATUS_PASSIVE);")
string(FIND "${tray_code}" "${old_destroy}" destroy_position)
if(destroy_position EQUAL -1)
  message(FATAL_ERROR "tray_manager 的实现已变化，请检查托盘资源释放补丁")
endif()
string(REPLACE "${old_destroy}"
  "    app_indicator_set_status(indicator, APP_INDICATOR_STATUS_PASSIVE);\n    g_clear_object(&indicator);\n    menu = nullptr;"
  tray_code "${tray_code}")
set(patched_tray "${CMAKE_CURRENT_BINARY_DIR}/tray_manager_plugin_patched.cc")
file(WRITE "${patched_tray}" "${tray_code}")
list(TRANSFORM tray_sources REPLACE "^tray_manager_plugin\\.cc$" "${patched_tray}")
set_property(TARGET tray_manager_plugin PROPERTY SOURCES "${tray_sources}")
target_include_directories(tray_manager_plugin PRIVATE "${tray_source_dir}")
