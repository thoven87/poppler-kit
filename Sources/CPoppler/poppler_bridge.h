#pragma once

#include <poppler-version.h>  // POPPLER_VERSION_MAJOR / _MINOR / _MICRO
#include <poppler-document.h>
#include <poppler-page.h>
#include <poppler-image.h>
#include <poppler-global.h>
#include <poppler-page-renderer.h>
#include <poppler-toc.h>
#include <poppler-embedded-file.h>
#include <poppler-destination.h>
#include <poppler-page-transition.h>
#include <poppler-font.h>
#include <string>

// ─────────────────────────────────────────────────────────────────────────────
// Minimum poppler version required by PopplerKit.
//
//   PopplerKit requires poppler 26.04.0 or later.
//   Tested against 26.05.0 in CI (built from source on Ubuntu 24.04).
//
//   macOS:  brew install pkg-config poppler
//           (Homebrew currently ships 26.04.0)
//
//   Linux:  build poppler 26.x from source — Ubuntu 24.04 provides all deps.
//           See GettingStarted in the DocC docs or the CI workflows.
//
// Encoding: major*10000 + minor*100 + micro  (e.g. 26.04.0 → 260400)
// ─────────────────────────────────────────────────────────────────────────────
#define POPPLER_KIT_ENCODE(maj, min, mic)  ((maj)*10000 + (min)*100 + (mic))
#define POPPLER_KIT_VERSION_INSTALLED \
    POPPLER_KIT_ENCODE(POPPLER_VERSION_MAJOR, POPPLER_VERSION_MINOR, POPPLER_VERSION_MICRO)
#define POPPLER_KIT_VERSION_MIN  POPPLER_KIT_ENCODE(26, 4, 0)

static_assert(
    POPPLER_KIT_VERSION_INSTALLED >= POPPLER_KIT_VERSION_MIN,
    "PopplerKit requires poppler >= 26.04.0.  "
    "macOS: brew install pkg-config poppler  "
    "Linux: build from source https://poppler.freedesktop.org/");

typedef void* PopplerDocPtr;
typedef void* PopplerPagePtr;

inline PopplerDocPtr poppler_document_load_from_file(const char* file_name) {
    return poppler::document::load_from_file(file_name);
}

inline PopplerDocPtr poppler_document_load_from_raw_data(const char* file_data, int length) {
    return poppler::document::load_from_raw_data(file_data, length);
}

inline void poppler_delete_document(PopplerDocPtr doc) {
    delete static_cast<poppler::document*>(doc);
}

inline int poppler_document_get_pages(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->pages();
}

inline PopplerPagePtr poppler_document_create_page(PopplerDocPtr doc, int index) {
    return static_cast<poppler::document*>(doc)->create_page(index);
}

inline void poppler_delete_page(PopplerPagePtr page) {
    delete static_cast<poppler::page*>(page);
}

inline std::string poppler_page_text_utf8(PopplerPagePtr page) {
    poppler::ustring ustr = static_cast<poppler::page*>(page)->text();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

// MARK: - Document Metadata

inline std::string poppler_document_get_title(PopplerDocPtr doc) {
    poppler::ustring ustr = static_cast<poppler::document*>(doc)->get_title();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline std::string poppler_document_get_author(PopplerDocPtr doc) {
    poppler::ustring ustr = static_cast<poppler::document*>(doc)->get_author();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline long poppler_document_get_creation_date(PopplerDocPtr doc) {
    return static_cast<long>(static_cast<poppler::document*>(doc)->get_creation_date_t());
}

// MARK: - Text Boxes & Layout

typedef struct {
    double left, top, right, bottom;
} PopplerRect;

typedef void* PopplerTextBoxListPtr;
typedef void* PopplerTextBoxPtr;

inline PopplerTextBoxListPtr poppler_page_get_text_list(PopplerPagePtr page) {
    // text_list returns std::vector by value. We move it to the heap.
    // Use text_list_include_font (1) to ensure font information is extracted.
    auto list = new std::vector<poppler::text_box>(static_cast<poppler::page*>(page)->text_list(poppler::page::text_list_include_font));
    return list;
}

inline void poppler_delete_text_list(PopplerTextBoxListPtr list) {
    delete static_cast<std::vector<poppler::text_box>*>(list);
}

inline int poppler_text_list_get_size(PopplerTextBoxListPtr list) {
    return static_cast<std::vector<poppler::text_box>*>(list)->size();
}

inline PopplerTextBoxPtr poppler_text_list_get_item(PopplerTextBoxListPtr list, int index) {
    auto& vec = *static_cast<std::vector<poppler::text_box>*>(list);
    return &vec[index];
}

inline std::string poppler_text_box_get_text_utf8(PopplerTextBoxPtr box) {
    poppler::ustring ustr = static_cast<poppler::text_box*>(box)->text();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline PopplerRect poppler_text_box_get_bbox(PopplerTextBoxPtr box) {
    poppler::rectf r = static_cast<poppler::text_box*>(box)->bbox();
    return { r.left(), r.top(), r.right(), r.bottom() };
}

inline double poppler_text_box_get_font_size(PopplerTextBoxPtr box) {
    return static_cast<poppler::text_box*>(box)->get_font_size();
}

inline std::string poppler_text_box_get_font_name(PopplerTextBoxPtr box) {
    return static_cast<poppler::text_box*>(box)->get_font_name();
}

inline int poppler_text_box_get_rotation(PopplerTextBoxPtr box) {
    return static_cast<poppler::text_box*>(box)->rotation();
}

inline bool poppler_text_box_has_space_after(PopplerTextBoxPtr box) {
    return static_cast<poppler::text_box*>(box)->has_space_after();
}

inline bool poppler_text_box_has_font_info(PopplerTextBoxPtr box) {
    return static_cast<poppler::text_box*>(box)->has_font_info();
}

// MARK: - Image Rendering

typedef void* PopplerRendererPtr;
typedef void* PopplerImagePtr;

inline PopplerRendererPtr poppler_renderer_create() {
    return new poppler::page_renderer();
}
inline void poppler_renderer_delete(PopplerRendererPtr renderer) {
    delete static_cast<poppler::page_renderer*>(renderer);
}
inline void poppler_renderer_set_render_hint(PopplerRendererPtr renderer, int hint, bool on) {
    static_cast<poppler::page_renderer*>(renderer)->set_render_hint(static_cast<poppler::page_renderer::render_hint>(hint), on);
}
inline PopplerImagePtr poppler_renderer_render_page(PopplerRendererPtr renderer, PopplerPagePtr page, double xres, double yres) {
    // page_renderer returns poppler::image by value, we move it to the heap.
    poppler::image img = static_cast<poppler::page_renderer*>(renderer)->render_page(static_cast<poppler::page*>(page), xres, yres);
    return new poppler::image(img);
}

inline void poppler_image_delete(PopplerImagePtr image) {
    delete static_cast<poppler::image*>(image);
}
inline bool poppler_image_is_valid(PopplerImagePtr image) {
    return static_cast<poppler::image*>(image)->is_valid();
}
inline int poppler_image_get_width(PopplerImagePtr image) {
    return static_cast<poppler::image*>(image)->width();
}
inline int poppler_image_get_height(PopplerImagePtr image) {
    return static_cast<poppler::image*>(image)->height();
}
inline int poppler_image_get_bytes_per_row(PopplerImagePtr image) {
    return static_cast<poppler::image*>(image)->bytes_per_row();
}
inline const char* poppler_image_get_data(PopplerImagePtr image) {
    return static_cast<poppler::image*>(image)->const_data();
}
inline int poppler_image_get_format(PopplerImagePtr image) {
    return static_cast<int>(static_cast<poppler::image*>(image)->format());
}

// MARK: - Table of Contents (TOC)

typedef void* PopplerTOCPtr;
typedef void* PopplerTOCItemPtr;
typedef void* PopplerTOCItemListPtr;

inline PopplerTOCPtr poppler_document_create_toc(PopplerDocPtr doc) {
    poppler::toc* t = static_cast<poppler::document*>(doc)->create_toc();
    return t; // Can be null
}
inline void poppler_delete_toc(PopplerTOCPtr toc) {
    delete static_cast<poppler::toc*>(toc);
}
inline PopplerTOCItemPtr poppler_toc_get_root(PopplerTOCPtr toc) {
    return static_cast<poppler::toc*>(toc)->root();
}
inline std::string poppler_toc_item_get_title(PopplerTOCItemPtr item) {
    poppler::ustring ustr = static_cast<poppler::toc_item*>(item)->title();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}
inline bool poppler_toc_item_is_open(PopplerTOCItemPtr item) {
    return static_cast<poppler::toc_item*>(item)->is_open();
}
inline PopplerTOCItemListPtr poppler_toc_item_get_children(PopplerTOCItemPtr item) {
    auto list = new std::vector<poppler::toc_item*>(static_cast<poppler::toc_item*>(item)->children());
    return list;
}
inline void poppler_delete_toc_item_list(PopplerTOCItemListPtr list) {
    delete static_cast<std::vector<poppler::toc_item*>*>(list);
}
inline int poppler_toc_item_list_get_size(PopplerTOCItemListPtr list) {
    return static_cast<std::vector<poppler::toc_item*>*>(list)->size();
}
inline PopplerTOCItemPtr poppler_toc_item_list_get_item(PopplerTOCItemListPtr list, int index) {
    auto& vec = *static_cast<std::vector<poppler::toc_item*>*>(list);
    return vec[index];
}

// MARK: - Embedded Files

typedef void* PopplerEmbeddedFileListPtr;
typedef void* PopplerEmbeddedFilePtr;
typedef void* PopplerByteArrayPtr;

inline PopplerEmbeddedFileListPtr poppler_document_get_embedded_files(PopplerDocPtr doc) {
    auto list = new std::vector<poppler::embedded_file*>(static_cast<poppler::document*>(doc)->embedded_files());
    return list;
}
inline void poppler_delete_embedded_file_list(PopplerEmbeddedFileListPtr list) {
    auto vec = static_cast<std::vector<poppler::embedded_file*>*>(list);
    for (auto f : *vec) { delete f; }
    delete vec;
}
inline int poppler_embedded_file_list_get_size(PopplerEmbeddedFileListPtr list) {
    return static_cast<std::vector<poppler::embedded_file*>*>(list)->size();
}
inline PopplerEmbeddedFilePtr poppler_embedded_file_list_get_item(PopplerEmbeddedFileListPtr list, int index) {
    auto& vec = *static_cast<std::vector<poppler::embedded_file*>*>(list);
    return vec[index];
}
inline std::string poppler_embedded_file_get_name(PopplerEmbeddedFilePtr file) {
    // name() returns std::string directly in the poppler-cpp wrapper.
    // unicodeName() is a GLib/Qt API and does not exist in poppler-cpp.
    return static_cast<poppler::embedded_file*>(file)->name();
}
inline std::string poppler_embedded_file_get_mime_type(PopplerEmbeddedFilePtr file) {
    return static_cast<poppler::embedded_file*>(file)->mime_type();
}
inline int poppler_embedded_file_get_size(PopplerEmbeddedFilePtr file) {
    return static_cast<poppler::embedded_file*>(file)->size();
}
inline PopplerByteArrayPtr poppler_embedded_file_get_data(PopplerEmbeddedFilePtr file) {
    auto arr = new poppler::byte_array(static_cast<poppler::embedded_file*>(file)->data());
    return arr;
}
inline void poppler_delete_byte_array(PopplerByteArrayPtr arr) {
    delete static_cast<poppler::byte_array*>(arr);
}
inline const char* poppler_byte_array_get_data(PopplerByteArrayPtr arr) {
    return static_cast<poppler::byte_array*>(arr)->data();
}
inline int poppler_byte_array_get_size(PopplerByteArrayPtr arr) {
    return static_cast<poppler::byte_array*>(arr)->size();
}

// MARK: - Destinations

typedef void* PopplerDestinationMapPtr;
typedef void* PopplerDestinationListPtr;
typedef void* PopplerDestinationPtr;

inline PopplerDestinationMapPtr poppler_document_create_destination_map(PopplerDocPtr doc) {
    auto m = new std::map<std::string, poppler::destination>(static_cast<poppler::document*>(doc)->create_destination_map());
    return m;
}
inline void poppler_delete_destination_map(PopplerDestinationMapPtr map) {
    delete static_cast<std::map<std::string, poppler::destination>*>(map);
}
inline PopplerDestinationListPtr poppler_destination_map_to_list(PopplerDestinationMapPtr map) {
    auto vec = new std::vector<std::pair<std::string, poppler::destination*>>();
    for (auto& pair : *static_cast<std::map<std::string, poppler::destination>*>(map)) {
        vec->push_back({pair.first, &pair.second});
    }
    return vec;
}
inline void poppler_delete_destination_list(PopplerDestinationListPtr list) {
    delete static_cast<std::vector<std::pair<std::string, poppler::destination*>>*>(list);
}
inline int poppler_destination_list_get_size(PopplerDestinationListPtr list) {
    return static_cast<std::vector<std::pair<std::string, poppler::destination*>>*>(list)->size();
}
inline const char* poppler_destination_list_get_name(PopplerDestinationListPtr list, int index) {
    return (*static_cast<std::vector<std::pair<std::string, poppler::destination*>>*>(list))[index].first.c_str();
}
inline PopplerDestinationPtr poppler_destination_list_get_dest(PopplerDestinationListPtr list, int index) {
    return (*static_cast<std::vector<std::pair<std::string, poppler::destination*>>*>(list))[index].second;
}
inline int poppler_destination_get_page_number(PopplerDestinationPtr dest) {
    return static_cast<poppler::destination*>(dest)->page_number();
}
inline double poppler_destination_get_left(PopplerDestinationPtr dest) {
    return static_cast<poppler::destination*>(dest)->left();
}
inline double poppler_destination_get_top(PopplerDestinationPtr dest) {
    return static_cast<poppler::destination*>(dest)->top();
}
inline double poppler_destination_get_zoom(PopplerDestinationPtr dest) {
    return static_cast<poppler::destination*>(dest)->zoom();
}

// MARK: - Fonts

typedef void* PopplerFontIteratorPtr;
typedef void* PopplerFontInfoListPtr;
typedef void* PopplerFontInfoPtr;

inline PopplerFontIteratorPtr poppler_document_create_font_iterator(PopplerDocPtr doc, int start_page) {
    return static_cast<poppler::document*>(doc)->create_font_iterator(start_page);
}
inline void poppler_delete_font_iterator(PopplerFontIteratorPtr iter) {
    delete static_cast<poppler::font_iterator*>(iter);
}
inline bool poppler_font_iterator_has_next(PopplerFontIteratorPtr iter) {
    return static_cast<poppler::font_iterator*>(iter)->has_next();
}
inline PopplerFontInfoListPtr poppler_font_iterator_next(PopplerFontIteratorPtr iter) {
    auto vec = new std::vector<poppler::font_info>(static_cast<poppler::font_iterator*>(iter)->next());
    return vec;
}
inline void poppler_delete_font_info_list(PopplerFontInfoListPtr list) {
    delete static_cast<std::vector<poppler::font_info>*>(list);
}
inline int poppler_font_info_list_get_size(PopplerFontInfoListPtr list) {
    return static_cast<std::vector<poppler::font_info>*>(list)->size();
}
inline PopplerFontInfoPtr poppler_font_info_list_get_item(PopplerFontInfoListPtr list, int index) {
    return &(*static_cast<std::vector<poppler::font_info>*>(list))[index];
}
inline std::string poppler_font_info_get_name(PopplerFontInfoPtr font) {
    return static_cast<poppler::font_info*>(font)->name();
}
inline std::string poppler_font_info_get_file(PopplerFontInfoPtr font) {
    return static_cast<poppler::font_info*>(font)->file();
}
inline bool poppler_font_info_is_embedded(PopplerFontInfoPtr font) {
    return static_cast<poppler::font_info*>(font)->is_embedded();
}

// MARK: - Page Transitions

typedef void* PopplerPageTransitionPtr;

inline PopplerPageTransitionPtr poppler_page_get_transition(PopplerPagePtr page) {
    poppler::page_transition* t = static_cast<poppler::page*>(page)->transition();
    return t; // can be null
}
inline void poppler_delete_page_transition(PopplerPageTransitionPtr transition) {
    delete static_cast<poppler::page_transition*>(transition);
}
inline int poppler_page_transition_get_type(PopplerPageTransitionPtr transition) {
    return static_cast<int>(static_cast<poppler::page_transition*>(transition)->type());
}
inline double poppler_page_transition_get_duration(PopplerPageTransitionPtr transition) {
    return static_cast<poppler::page_transition*>(transition)->durationReal();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Password-protected Document Loading
// ─────────────────────────────────────────────────────────────────────────────

inline PopplerDocPtr poppler_document_load_from_file_with_password(
    const char* file_name,
    const char* owner_password,
    const char* user_password)
{
    if (!file_name) return nullptr;
    return poppler::document::load_from_file(
        std::string(file_name),
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    );
}

inline PopplerDocPtr poppler_document_load_from_raw_data_with_password(
    const char* file_data,
    int         length,
    const char* owner_password,
    const char* user_password)
{
    if (!file_data || length <= 0) return nullptr;
    return poppler::document::load_from_raw_data(
        file_data, length,
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Extended Document Metadata
// ─────────────────────────────────────────────────────────────────────────────

inline std::string poppler_document_get_subject(PopplerDocPtr doc) {
    poppler::ustring u = static_cast<poppler::document*>(doc)->get_subject();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_keywords(PopplerDocPtr doc) {
    poppler::ustring u = static_cast<poppler::document*>(doc)->get_keywords();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_creator(PopplerDocPtr doc) {
    poppler::ustring u = static_cast<poppler::document*>(doc)->get_creator();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_producer(PopplerDocPtr doc) {
    poppler::ustring u = static_cast<poppler::document*>(doc)->get_producer();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline long poppler_document_get_modification_date(PopplerDocPtr doc) {
    return static_cast<long>(static_cast<poppler::document*>(doc)->get_modification_date_t());
}

inline bool poppler_document_is_encrypted(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->is_encrypted();
}

inline bool poppler_document_is_locked(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->is_locked();
}

inline int poppler_document_get_page_layout(PopplerDocPtr doc) {
    return static_cast<int>(static_cast<poppler::document*>(doc)->page_layout());
}

inline int poppler_document_get_page_mode(PopplerDocPtr doc) {
    return static_cast<int>(static_cast<poppler::document*>(doc)->page_mode());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Dimensions
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the media box of a page in PDF points (1 pt = 1/72 inch).
/// Explicitly passes poppler::media_box — the no-arg default is crop_box.
inline PopplerRect poppler_page_get_media_box(PopplerPagePtr page) {
    poppler::rectf r = static_cast<poppler::page*>(page)->page_rect(poppler::media_box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

/// Returns any of the five PDF page boxes.
/// box_type: 0=media_box, 1=crop_box, 2=bleed_box, 3=trim_box, 4=art_box
inline PopplerRect poppler_page_get_page_rect(PopplerPagePtr page, int box_type) {
    auto box = static_cast<poppler::page_box_enum>(box_type);
    poppler::rectf r = static_cast<poppler::page*>(page)->page_rect(box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Extraction with Layout
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts the full text of a page using an explicit layout algorithm.
/// @param layout  0 = physical_layout, 1 = raw_order_layout, 2 = non_raw_non_physical_layout (poppler >= 0.88)
/// Uses text(page_rect(), layout_mode) for maximum version compatibility (available since poppler 0.16).
inline std::string poppler_page_text_utf8_with_layout(PopplerPagePtr page, int layout) {
    auto* p    = static_cast<poppler::page*>(page);
    auto  mode = static_cast<poppler::page::text_layout_enum>(layout);
    poppler::ustring u = p->text(p->page_rect(), mode);
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Image Encoding
// ─────────────────────────────────────────────────────────────────────────────

/// Saves a rendered poppler::image to a file.
/// @param format  "png", "jpeg", or "tiff"
/// @param dpi     DPI hint embedded in the file header; pass -1 to use the library default.
inline bool poppler_image_save_to_path(
    PopplerImagePtr image,
    const char*     file_path,
    const char*     format,
    int             dpi)
{
    if (!file_path || !format) return false;
    return static_cast<poppler::image*>(image)->save(
        std::string(file_path), std::string(format), dpi);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Typed Render-Hint Setters
// Avoids exposing magic integers to the Swift layer.
// ─────────────────────────────────────────────────────────────────────────────

inline void poppler_renderer_set_antialiasing(PopplerRendererPtr r, bool on) {
    static_cast<poppler::page_renderer*>(r)->set_render_hint(
        poppler::page_renderer::antialiasing, on);
}

inline void poppler_renderer_set_text_antialiasing(PopplerRendererPtr r, bool on) {
    static_cast<poppler::page_renderer*>(r)->set_render_hint(
        poppler::page_renderer::text_antialiasing, on);
}

inline void poppler_renderer_set_text_hinting(PopplerRendererPtr r, bool on) {
    static_cast<poppler::page_renderer*>(r)->set_render_hint(
        poppler::page_renderer::text_hinting, on);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PDF Version
// ─────────────────────────────────────────────────────────────────────────────

inline void poppler_document_get_pdf_version(PopplerDocPtr doc, int* major, int* minor) {
    static_cast<poppler::document*>(doc)->get_pdf_version(major, minor);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document State
// ─────────────────────────────────────────────────────────────────────────────

inline bool poppler_document_is_linearized(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->is_linearized();
}

inline bool poppler_document_has_embedded_files(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->has_embedded_files();
}

/// Attempts to unlock an encrypted document after load.
/// Returns true if the document is now unlocked.
inline bool poppler_document_unlock(
    PopplerDocPtr doc,
    const char*   owner_password,
    const char*   user_password)
{
    return static_cast<poppler::document*>(doc)->unlock(
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Label, Orientation & Duration
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the logical page label (e.g. "iii", "iv", "1") as UTF-8.
inline std::string poppler_page_get_label(PopplerPagePtr page) {
    poppler::ustring u = static_cast<poppler::page*>(page)->label();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

/// Returns the page orientation: 0=landscape, 1=portrait, 2=seascape, 3=upside_down.
inline int poppler_page_get_orientation(PopplerPagePtr page) {
    return static_cast<int>(static_cast<poppler::page*>(page)->orientation());
}

/// Returns the presentation slide duration in seconds, or -1 if not set.
inline double poppler_page_get_duration(PopplerPagePtr page) {
    return static_cast<poppler::page*>(page)->duration();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Region Text Extraction
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts text within a rectangle (in PDF points) using the library default layout.
inline std::string poppler_page_text_in_rect(
    PopplerPagePtr page,
    double left, double top, double right, double bottom)
{
    auto* p = static_cast<poppler::page*>(page);
    poppler::rectf r(left, top, right - left, bottom - top);
    poppler::ustring u = p->text(r);
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

/// Extracts text within a rectangle using an explicit layout algorithm.
/// @param layout  0=physical_layout, 1=raw_order_layout, 2=non_raw_non_physical_layout
inline std::string poppler_page_text_in_rect_with_layout(
    PopplerPagePtr page,
    double left, double top, double right, double bottom,
    int layout)
{
    auto* p    = static_cast<poppler::page*>(page);
    auto  mode = static_cast<poppler::page::text_layout_enum>(layout);
    poppler::rectf r(left, top, right - left, bottom - top);
    poppler::ustring u = p->text(r, mode);
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Search
// ─────────────────────────────────────────────────────────────────────────────

/// Searches for UTF-8 text on a page.
///
/// On entry, [left, top, right, bottom] is the starting rectangle (pass all zeros
/// for direction=from_top or all page-rect values for direction=from_bottom).
/// On a successful return, the four pointers are updated to the match bounding box.
///
/// @param direction       0=from_top, 1=next_result, 2=from_bottom, 3=previous_result
/// @param case_sensitivity 0=case_sensitive, 1=case_insensitive
/// @return true if a match was found.
inline bool poppler_page_search(
    PopplerPagePtr page,
    const char*    text,
    double* left, double* top, double* right, double* bottom,
    int direction,
    int case_sensitivity)
{
    if (!text || !left || !top || !right || !bottom) return false;
    auto* p = static_cast<poppler::page*>(page);
    poppler::ustring usearch = poppler::ustring::from_utf8(text, -1);

    double w = *right - *left, h = *bottom - *top;
    poppler::rectf r(*left, *top, w > 0 ? w : 0, h > 0 ? h : 0);

    // search_direction_enum is a nested type of poppler::page;
    // case_sensitivity_enum lives in the poppler:: namespace.
    bool found = p->search(
        usearch, r,
        static_cast<poppler::page::search_direction_enum>(direction),
        static_cast<poppler::case_sensitivity_enum>(case_sensitivity));

    if (found) {
        *left = r.left(); *top = r.top(); *right = r.right(); *bottom = r.bottom();
    }
    return found;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Destination Type
// ─────────────────────────────────────────────────────────────────────────────

/// Returns destination type: unknown=0, xyz=1, fit=2, fit_h=3, fit_v=4,
///                           fit_b=5, fit_b_h=6, fit_b_v=7, fit_r=8.
inline int poppler_destination_get_type(PopplerDestinationPtr dest) {
    return static_cast<int>(static_cast<poppler::destination*>(dest)->type());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Font Info Extensions
// ─────────────────────────────────────────────────────────────────────────────

/// Returns font type: unknown=0, type1=1, type1c=2, type1_cot=3, type3=4,
///   truetype=5, truetype_ot=6, cid_type0=7, cid_type0c=8, cid_type0c_ot=9,
///   cid_type2=10, cid_type2_ot=11.
inline int poppler_font_info_get_type(PopplerFontInfoPtr font) {
    return static_cast<int>(static_cast<poppler::font_info*>(font)->type());
}

/// Returns true if the font is embedded as a subset (only glyphs used are present).
inline bool poppler_font_info_is_subset(PopplerFontInfoPtr font) {
    return static_cast<poppler::font_info*>(font)->is_subset();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Embedded File Extensions
// ─────────────────────────────────────────────────────────────────────────────

inline bool poppler_embedded_file_is_valid(PopplerEmbeddedFilePtr file) {
    return static_cast<poppler::embedded_file*>(file)->is_valid();
}

inline std::string poppler_embedded_file_get_description(PopplerEmbeddedFilePtr file) {
    poppler::ustring u = static_cast<poppler::embedded_file*>(file)->description();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline long poppler_embedded_file_get_creation_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(static_cast<poppler::embedded_file*>(file)->creation_date_t());
}

inline long poppler_embedded_file_get_modification_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(static_cast<poppler::embedded_file*>(file)->modification_date_t());
}

/// Returns the file checksum as a lowercase hex string (empty if unavailable).
inline std::string poppler_embedded_file_get_checksum(PopplerEmbeddedFilePtr file) {
    // checksum() returns poppler::byte_array (std::vector<char>), not std::string
    poppler::byte_array raw = static_cast<poppler::embedded_file*>(file)->checksum();
    if (raw.empty()) return {};
    static const char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(raw.size() * 2);
    for (unsigned char c : raw) {
        result += hex[c >> 4];
        result += hex[c & 0xf];
    }
    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Transition Extensions
// ─────────────────────────────────────────────────────────────────────────────

/// Transition axis alignment: 0=horizontal, 1=vertical.
inline int poppler_page_transition_get_alignment(PopplerPageTransitionPtr t) {
    return static_cast<int>(static_cast<poppler::page_transition*>(t)->alignment());
}

/// Motion direction: 0=inward (toward center), 1=outward (toward edges).
inline int poppler_page_transition_get_motion_direction(PopplerPageTransitionPtr t) {
    return static_cast<int>(static_cast<poppler::page_transition*>(t)->direction());
}

/// Direction of motion in degrees (e.g. 0=left-to-right, 90=bottom-to-top).
inline int poppler_page_transition_get_angle(PopplerPageTransitionPtr t) {
    return static_cast<int>(static_cast<poppler::page_transition*>(t)->angle());
}

/// Scale factor for fly transitions (0.0–1.0).
inline double poppler_page_transition_get_scale(PopplerPageTransitionPtr t) {
    return static_cast<poppler::page_transition*>(t)->scale();
}

/// Whether the transition uses a rectangular rather than circular region.
inline bool poppler_page_transition_is_rectangular(PopplerPageTransitionPtr t) {
    return static_cast<poppler::page_transition*>(t)->is_rectangular();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Permissions
// ─────────────────────────────────────────────────────────────────────────────

/// Checks a single permission flag.
/// perm values (poppler::permission_enum):
///   0=perm_print, 1=perm_change, 2=perm_copy, 3=perm_add_notes,
///   4=perm_fill_forms, 5=perm_accessibility, 6=perm_assemble, 7=perm_print_high_resolution
inline bool poppler_document_has_permission(PopplerDocPtr doc, int perm) {
    return static_cast<poppler::document*>(doc)->has_permission(
        static_cast<poppler::permission_enum>(perm));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Form Type & JavaScript
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the form type: 0=none, 1=acro (AcroForms), 2=xfa (Adobe XFA).
/// form_type is an enum class inside poppler::document.
inline int poppler_document_get_form_type(PopplerDocPtr doc) {
    return static_cast<int>(static_cast<poppler::document*>(doc)->form_type());
}

/// Returns true if the document contains embedded JavaScript.
inline bool poppler_document_has_javascript(PopplerDocPtr doc) {
    return static_cast<poppler::document*>(doc)->has_javascript();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - XMP Metadata & PDF ID
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the raw XMP metadata packet as a UTF-8 string (empty if absent).
inline std::string poppler_document_get_metadata(PopplerDocPtr doc) {
    poppler::ustring u = static_cast<poppler::document*>(doc)->metadata();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

/// Returns true if get_pdf_id() produced a non-empty result.
inline bool poppler_document_has_pdf_id(PopplerDocPtr doc) {
    std::string p, u;
    return static_cast<poppler::document*>(doc)->get_pdf_id(&p, &u);
}

/// Returns the permanent PDF document identifier (hex string).
inline std::string poppler_document_get_permanent_id(PopplerDocPtr doc) {
    std::string p, u;
    static_cast<poppler::document*>(doc)->get_pdf_id(&p, &u);
    return p;
}

/// Returns the update PDF document identifier (hex string, changes on each save).
inline std::string poppler_document_get_update_id(PopplerDocPtr doc) {
    std::string p, u;
    static_cast<poppler::document*>(doc)->get_pdf_id(&p, &u);
    return u;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Info Dictionary (custom metadata keys)
// ─────────────────────────────────────────────────────────────────────────────

typedef void* PopplerStringListPtr;

inline PopplerStringListPtr poppler_document_get_info_keys(PopplerDocPtr doc) {
    auto vec = new std::vector<std::string>(
        static_cast<poppler::document*>(doc)->info_keys());
    return vec;
}

inline void poppler_delete_string_list(PopplerStringListPtr list) {
    delete static_cast<std::vector<std::string>*>(list);
}

inline int poppler_string_list_get_size(PopplerStringListPtr list) {
    return static_cast<int>(
        static_cast<std::vector<std::string>*>(list)->size());
}

inline std::string poppler_string_list_get_item(PopplerStringListPtr list, int index) {
    return (*static_cast<std::vector<std::string>*>(list))[index];
}

/// Returns the UTF-8 value for an arbitrary info-dictionary key (empty if absent).
inline std::string poppler_document_get_info_key(PopplerDocPtr doc, const char* key) {
    if (!key) return {};
    poppler::ustring uval = static_cast<poppler::document*>(doc)->info_key(std::string(key));
    poppler::byte_array b = uval.to_utf8();
    return std::string(b.begin(), b.end());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page by Label
// ─────────────────────────────────────────────────────────────────────────────

/// Finds the page with the given logical label (e.g. "iii", "1", "A-1").
/// Returns nullptr if no matching page exists.
inline PopplerPagePtr poppler_document_create_page_by_label(
    PopplerDocPtr doc, const char* label)
{
    if (!label) return nullptr;
    poppler::ustring ulabel = poppler::ustring::from_utf8(label, -1);
    return static_cast<poppler::document*>(doc)->create_page(ulabel);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Persistence
// ─────────────────────────────────────────────────────────────────────────────

/// Saves the document (with any in-memory modifications) to a file.
inline bool poppler_document_save(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return static_cast<poppler::document*>(doc)->save(std::string(file_path));
}

/// Saves an unmodified byte-for-byte copy of the document to a file.
inline bool poppler_document_save_a_copy(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return static_cast<poppler::document*>(doc)->save_a_copy(std::string(file_path));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Box: Character Bounding Boxes & Writing Mode
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the number of UCS4 code points in the text box's text.
inline int poppler_text_box_get_text_length(PopplerTextBoxPtr box) {
    return static_cast<int>(
        static_cast<poppler::text_box*>(box)->text().size());
}

/// Returns the bounding box for the i-th glyph (in PDF points).
/// Returns {0,0,0,0} for out-of-range indices.
inline PopplerRect poppler_text_box_get_char_bbox(PopplerTextBoxPtr box, int index) {
    poppler::rectf r = static_cast<poppler::text_box*>(box)->char_bbox(
        static_cast<size_t>(index));
    return { r.left(), r.top(), r.right(), r.bottom() };
}

/// Returns the writing mode for the i-th glyph.
/// writing_mode_enum is a nested type of text_box: invalid=-1, horizontal=0, vertical=1.
inline int poppler_text_box_get_wmode(PopplerTextBoxPtr box, int index) {
    return static_cast<int>(
        static_cast<poppler::text_box*>(box)->get_wmode(index));
}
