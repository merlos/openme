idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES openmelib esp_wifi esp_event nvs_flash
)
