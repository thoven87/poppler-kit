#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Opaque handle pointer types
// ─────────────────────────────────────────────────────────────────────────────

struct PopplerDocHandle;              typedef struct PopplerDocHandle              *PopplerDocPtr;
struct PopplerPageHandle;             typedef struct PopplerPageHandle             *PopplerPagePtr;
struct PopplerRendererHandle;         typedef struct PopplerRendererHandle         *PopplerRendererPtr;
struct PopplerImageHandle;            typedef struct PopplerImageHandle            *PopplerImagePtr;
struct PopplerTextBoxListHandle;      typedef struct PopplerTextBoxListHandle      *PopplerTextBoxListPtr;
struct PopplerTextBoxHandle;          typedef struct PopplerTextBoxHandle          *PopplerTextBoxPtr;
struct PopplerTOCHandle;              typedef struct PopplerTOCHandle              *PopplerTOCPtr;
struct PopplerTOCItemHandle;          typedef struct PopplerTOCItemHandle          *PopplerTOCItemPtr;
struct PopplerTOCItemListHandle;      typedef struct PopplerTOCItemListHandle      *PopplerTOCItemListPtr;
struct PopplerEmbeddedFileListHandle; typedef struct PopplerEmbeddedFileListHandle *PopplerEmbeddedFileListPtr;
struct PopplerEmbeddedFileHandle;     typedef struct PopplerEmbeddedFileHandle     *PopplerEmbeddedFilePtr;
struct PopplerByteArrayHandle;        typedef struct PopplerByteArrayHandle        *PopplerByteArrayPtr;
struct PopplerDestinationMapHandle;   typedef struct PopplerDestinationMapHandle   *PopplerDestinationMapPtr;
struct PopplerDestinationListHandle;  typedef struct PopplerDestinationListHandle  *PopplerDestinationListPtr;
struct PopplerDestinationHandle;      typedef struct PopplerDestinationHandle      *PopplerDestinationPtr;
struct PopplerFontIteratorHandle;     typedef struct PopplerFontIteratorHandle     *PopplerFontIteratorPtr;
struct PopplerFontInfoListHandle;     typedef struct PopplerFontInfoListHandle     *PopplerFontInfoListPtr;
struct PopplerFontInfoHandle;         typedef struct PopplerFontInfoHandle         *PopplerFontInfoPtr;
struct PopplerPageTransitionHandle;   typedef struct PopplerPageTransitionHandle   *PopplerPageTransitionPtr;
struct PopplerStringListHandle;       typedef struct PopplerStringListHandle       *PopplerStringListPtr;

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Plain C rect
// ─────────────────────────────────────────────────────────────────────────────

typedef struct {
    double left, top, right, bottom;
} PopplerRect;

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Loading
// ─────────────────────────────────────────────────────────────────────────────

PopplerDocPtr poppler_document_load_from_file(const char* file_name);
PopplerDocPtr poppler_document_load_from_raw_data(const char* file_data, int length);
PopplerDocPtr poppler_document_load_from_file_with_password(
    const char* file_name, const char* owner_password, const char* user_password);
PopplerDocPtr poppler_document_load_from_raw_data_with_password(
    const char* file_data, int length, const char* owner_password, const char* user_password);
void poppler_delete_document(PopplerDocPtr doc);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Properties
// ─────────────────────────────────────────────────────────────────────────────

int  poppler_document_get_pages(PopplerDocPtr doc);
void poppler_document_get_pdf_version(PopplerDocPtr doc, int* major, int* minor);
int  poppler_document_get_page_layout(PopplerDocPtr doc);
int  poppler_document_get_page_mode(PopplerDocPtr doc);
int  poppler_document_get_form_type(PopplerDocPtr doc);
bool poppler_document_is_encrypted(PopplerDocPtr doc);
bool poppler_document_is_locked(PopplerDocPtr doc);
bool poppler_document_is_linearized(PopplerDocPtr doc);
bool poppler_document_has_embedded_files(PopplerDocPtr doc);
bool poppler_document_has_javascript(PopplerDocPtr doc);
bool poppler_document_has_permission(PopplerDocPtr doc, int perm);
bool poppler_document_has_pdf_id(PopplerDocPtr doc);
bool poppler_document_unlock(PopplerDocPtr doc, const char* owner_password, const char* user_password);
bool poppler_document_save(PopplerDocPtr doc, const char* file_path);
bool poppler_document_save_a_copy(PopplerDocPtr doc, const char* file_path);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Metadata
// String-returning functions always return a valid UTF-8 C string; never NULL.
// An empty string ("") is returned when the field is absent.
// ─────────────────────────────────────────────────────────────────────────────

const char* poppler_document_get_title(PopplerDocPtr doc);
const char* poppler_document_get_author(PopplerDocPtr doc);
const char* poppler_document_get_subject(PopplerDocPtr doc);
const char* poppler_document_get_keywords(PopplerDocPtr doc);
const char* poppler_document_get_creator(PopplerDocPtr doc);
const char* poppler_document_get_producer(PopplerDocPtr doc);
const char* poppler_document_get_metadata(PopplerDocPtr doc);
const char* poppler_document_get_permanent_id(PopplerDocPtr doc);
const char* poppler_document_get_update_id(PopplerDocPtr doc);
long        poppler_document_get_creation_date(PopplerDocPtr doc);
long        poppler_document_get_modification_date(PopplerDocPtr doc);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Info Dictionary
// ─────────────────────────────────────────────────────────────────────────────

PopplerStringListPtr poppler_document_get_info_keys(PopplerDocPtr doc);
void        poppler_delete_string_list(PopplerStringListPtr list);
int         poppler_string_list_get_size(PopplerStringListPtr list);
const char* poppler_string_list_get_item(PopplerStringListPtr list, int index);
const char* poppler_document_get_info_key(PopplerDocPtr doc, const char* key);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pages
// ─────────────────────────────────────────────────────────────────────────────

PopplerPagePtr poppler_document_create_page(PopplerDocPtr doc, int index);
PopplerPagePtr poppler_document_create_page_by_label(PopplerDocPtr doc, const char* label);
void           poppler_delete_page(PopplerPagePtr page);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Properties
// ─────────────────────────────────────────────────────────────────────────────

PopplerRect poppler_page_get_media_box(PopplerPagePtr page);
PopplerRect poppler_page_get_page_rect(PopplerPagePtr page, int box_type);
int         poppler_page_get_orientation(PopplerPagePtr page);
double      poppler_page_get_duration(PopplerPagePtr page);
const char* poppler_page_get_label(PopplerPagePtr page);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Extraction
// ─────────────────────────────────────────────────────────────────────────────

const char* poppler_page_text_utf8(PopplerPagePtr page);
const char* poppler_page_text_utf8_with_layout(PopplerPagePtr page, int layout);
const char* poppler_page_text_in_rect(
    PopplerPagePtr page, double left, double top, double right, double bottom);
const char* poppler_page_text_in_rect_with_layout(
    PopplerPagePtr page, double left, double top, double right, double bottom, int layout);
bool poppler_page_search(
    PopplerPagePtr page, const char* text,
    double* left, double* top, double* right, double* bottom,
    int direction, int case_sensitivity);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Boxes
// ─────────────────────────────────────────────────────────────────────────────

PopplerTextBoxListPtr poppler_page_get_text_list(PopplerPagePtr page);
void           poppler_delete_text_list(PopplerTextBoxListPtr list);
int            poppler_text_list_get_size(PopplerTextBoxListPtr list);
PopplerTextBoxPtr poppler_text_list_get_item(PopplerTextBoxListPtr list, int index);
const char*    poppler_text_box_get_text_utf8(PopplerTextBoxPtr box);
PopplerRect    poppler_text_box_get_bbox(PopplerTextBoxPtr box);
double         poppler_text_box_get_font_size(PopplerTextBoxPtr box);
const char*    poppler_text_box_get_font_name(PopplerTextBoxPtr box);
int            poppler_text_box_get_rotation(PopplerTextBoxPtr box);
bool           poppler_text_box_has_space_after(PopplerTextBoxPtr box);
bool           poppler_text_box_has_font_info(PopplerTextBoxPtr box);
int            poppler_text_box_get_text_length(PopplerTextBoxPtr box);
PopplerRect    poppler_text_box_get_char_bbox(PopplerTextBoxPtr box, int index);
int            poppler_text_box_get_wmode(PopplerTextBoxPtr box, int index);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Image Rendering
// ─────────────────────────────────────────────────────────────────────────────

PopplerRendererPtr poppler_renderer_create(void);
void poppler_renderer_delete(PopplerRendererPtr renderer);
void poppler_renderer_set_render_hint(PopplerRendererPtr renderer, int hint, bool on);
void poppler_renderer_set_antialiasing(PopplerRendererPtr renderer, bool on);
void poppler_renderer_set_text_antialiasing(PopplerRendererPtr renderer, bool on);
void poppler_renderer_set_text_hinting(PopplerRendererPtr renderer, bool on);
PopplerImagePtr poppler_renderer_render_page(
    PopplerRendererPtr renderer, PopplerPagePtr page, double xres, double yres);
void        poppler_image_delete(PopplerImagePtr image);
bool        poppler_image_is_valid(PopplerImagePtr image);
int         poppler_image_get_width(PopplerImagePtr image);
int         poppler_image_get_height(PopplerImagePtr image);
int         poppler_image_get_bytes_per_row(PopplerImagePtr image);
const char* poppler_image_get_data(PopplerImagePtr image);
int         poppler_image_get_format(PopplerImagePtr image);
bool        poppler_image_save_to_path(
    PopplerImagePtr image, const char* file_path, const char* format, int dpi);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Table of Contents (TOC)
// ─────────────────────────────────────────────────────────────────────────────

PopplerTOCPtr     poppler_document_create_toc(PopplerDocPtr doc);
void              poppler_delete_toc(PopplerTOCPtr toc);
PopplerTOCItemPtr poppler_toc_get_root(PopplerTOCPtr toc);
const char*       poppler_toc_item_get_title(PopplerTOCItemPtr item);
bool              poppler_toc_item_is_open(PopplerTOCItemPtr item);
PopplerTOCItemListPtr poppler_toc_item_get_children(PopplerTOCItemPtr item);
void              poppler_delete_toc_item_list(PopplerTOCItemListPtr list);
int               poppler_toc_item_list_get_size(PopplerTOCItemListPtr list);
PopplerTOCItemPtr poppler_toc_item_list_get_item(PopplerTOCItemListPtr list, int index);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Embedded Files
// ─────────────────────────────────────────────────────────────────────────────

PopplerEmbeddedFileListPtr poppler_document_get_embedded_files(PopplerDocPtr doc);
void              poppler_delete_embedded_file_list(PopplerEmbeddedFileListPtr list);
int               poppler_embedded_file_list_get_size(PopplerEmbeddedFileListPtr list);
PopplerEmbeddedFilePtr poppler_embedded_file_list_get_item(
    PopplerEmbeddedFileListPtr list, int index);
bool        poppler_embedded_file_is_valid(PopplerEmbeddedFilePtr file);
const char* poppler_embedded_file_get_name(PopplerEmbeddedFilePtr file);
const char* poppler_embedded_file_get_mime_type(PopplerEmbeddedFilePtr file);
const char* poppler_embedded_file_get_description(PopplerEmbeddedFilePtr file);
const char* poppler_embedded_file_get_checksum(PopplerEmbeddedFilePtr file);
int         poppler_embedded_file_get_size(PopplerEmbeddedFilePtr file);
long        poppler_embedded_file_get_creation_date(PopplerEmbeddedFilePtr file);
long        poppler_embedded_file_get_modification_date(PopplerEmbeddedFilePtr file);
PopplerByteArrayPtr poppler_embedded_file_get_data(PopplerEmbeddedFilePtr file);
void        poppler_delete_byte_array(PopplerByteArrayPtr arr);
const char* poppler_byte_array_get_data(PopplerByteArrayPtr arr);
int         poppler_byte_array_get_size(PopplerByteArrayPtr arr);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Destinations
// ─────────────────────────────────────────────────────────────────────────────

PopplerDestinationMapPtr  poppler_document_create_destination_map(PopplerDocPtr doc);
void                      poppler_delete_destination_map(PopplerDestinationMapPtr map);
PopplerDestinationListPtr poppler_destination_map_to_list(PopplerDestinationMapPtr map);
void        poppler_delete_destination_list(PopplerDestinationListPtr list);
int         poppler_destination_list_get_size(PopplerDestinationListPtr list);
const char* poppler_destination_list_get_name(PopplerDestinationListPtr list, int index);
PopplerDestinationPtr poppler_destination_list_get_dest(
    PopplerDestinationListPtr list, int index);
int    poppler_destination_get_page_number(PopplerDestinationPtr dest);
double poppler_destination_get_left(PopplerDestinationPtr dest);
double poppler_destination_get_top(PopplerDestinationPtr dest);
double poppler_destination_get_zoom(PopplerDestinationPtr dest);
int    poppler_destination_get_type(PopplerDestinationPtr dest);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Fonts
// ─────────────────────────────────────────────────────────────────────────────

PopplerFontIteratorPtr poppler_document_create_font_iterator(PopplerDocPtr doc, int start_page);
void               poppler_delete_font_iterator(PopplerFontIteratorPtr iter);
bool               poppler_font_iterator_has_next(PopplerFontIteratorPtr iter);
PopplerFontInfoListPtr poppler_font_iterator_next(PopplerFontIteratorPtr iter);
void               poppler_delete_font_info_list(PopplerFontInfoListPtr list);
int                poppler_font_info_list_get_size(PopplerFontInfoListPtr list);
PopplerFontInfoPtr poppler_font_info_list_get_item(PopplerFontInfoListPtr list, int index);
const char* poppler_font_info_get_name(PopplerFontInfoPtr font);
const char* poppler_font_info_get_file(PopplerFontInfoPtr font);
bool        poppler_font_info_is_embedded(PopplerFontInfoPtr font);
bool        poppler_font_info_is_subset(PopplerFontInfoPtr font);
int         poppler_font_info_get_type(PopplerFontInfoPtr font);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Transitions
// ─────────────────────────────────────────────────────────────────────────────

PopplerPageTransitionPtr poppler_page_get_transition(PopplerPagePtr page);
void   poppler_delete_page_transition(PopplerPageTransitionPtr transition);
int    poppler_page_transition_get_type(PopplerPageTransitionPtr transition);
double poppler_page_transition_get_duration(PopplerPageTransitionPtr transition);
int    poppler_page_transition_get_alignment(PopplerPageTransitionPtr transition);
int    poppler_page_transition_get_motion_direction(PopplerPageTransitionPtr transition);
int    poppler_page_transition_get_angle(PopplerPageTransitionPtr transition);
double poppler_page_transition_get_scale(PopplerPageTransitionPtr transition);
bool   poppler_page_transition_is_rectangular(PopplerPageTransitionPtr transition);

#ifdef __cplusplus
} // extern "C"
#endif
