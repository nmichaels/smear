add_library(queue STATIC EXCLUDE_FROM_ALL)
target_include_directories(queue PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_sources(queue PRIVATE
  "posix/queue.c"
)
