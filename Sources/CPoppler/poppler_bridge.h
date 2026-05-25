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
#include <map>
#include <vector>

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

// MARK: - Opaque handle pointer types

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

// MARK: - Plain C rect (not a handle; do not change)

typedef struct {
    double left, top, right, bottom;
} PopplerRect;

#ifdef __cplusplus
// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Opaque handle <-> C++ type cast helpers
//
// Each opaque handle struct is an incomplete type whose pointer identity
// is reinterpreted as the matching C++ type.  This is safe because every
// handle is created by a `new CppType(...)` call inside this translation unit
// and destroyed by a matching `delete` inside the same unit.
// ─────────────────────────────────────────────────────────────────────────────

// Documents & pages
static inline poppler::document*       toDoc    (PopplerDocPtr        p) noexcept { return reinterpret_cast<poppler::document*>(p); }
static inline poppler::page*           toPage   (PopplerPagePtr        p) noexcept { return reinterpret_cast<poppler::page*>(p); }
static inline PopplerDocPtr            fromDoc  (poppler::document*    p) noexcept { return reinterpret_cast<PopplerDocPtr>(p); }
static inline PopplerPagePtr           fromPage (poppler::page*        p) noexcept { return reinterpret_cast<PopplerPagePtr>(p); }

// Renderer & image
static inline poppler::page_renderer*  toRenderer  (PopplerRendererPtr p) noexcept { return reinterpret_cast<poppler::page_renderer*>(p); }
static inline poppler::image*          toImage     (PopplerImagePtr    p) noexcept { return reinterpret_cast<poppler::image*>(p); }
static inline PopplerRendererPtr       fromRenderer(poppler::page_renderer* p) noexcept { return reinterpret_cast<PopplerRendererPtr>(p); }
static inline PopplerImagePtr          fromImage   (poppler::image*         p) noexcept { return reinterpret_cast<PopplerImagePtr>(p); }

// Text boxes
static inline std::vector<poppler::text_box>*  toTextList  (PopplerTextBoxListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::text_box>*>(p); }
static inline poppler::text_box*               toTextBox   (PopplerTextBoxPtr     p) noexcept { return reinterpret_cast<poppler::text_box*>(p); }
static inline PopplerTextBoxListPtr            fromTextList(std::vector<poppler::text_box>* p) noexcept { return reinterpret_cast<PopplerTextBoxListPtr>(p); }

// TOC
static inline poppler::toc*                    toTOC      (PopplerTOCPtr         p) noexcept { return reinterpret_cast<poppler::toc*>(p); }
static inline poppler::toc_item*               toTOCItem  (PopplerTOCItemPtr     p) noexcept { return reinterpret_cast<poppler::toc_item*>(p); }
static inline std::vector<poppler::toc_item*>* toTOCList  (PopplerTOCItemListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::toc_item*>*>(p); }
static inline PopplerTOCPtr                    fromTOC    (poppler::toc*         p) noexcept { return reinterpret_cast<PopplerTOCPtr>(p); }
static inline PopplerTOCItemListPtr            fromTOCList(std::vector<poppler::toc_item*>* p) noexcept { return reinterpret_cast<PopplerTOCItemListPtr>(p); }

// Embedded files
static inline std::vector<poppler::embedded_file*>* toFileList  (PopplerEmbeddedFileListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::embedded_file*>*>(p); }
static inline poppler::embedded_file*               toFile      (PopplerEmbeddedFilePtr     p) noexcept { return reinterpret_cast<poppler::embedded_file*>(p); }
static inline poppler::byte_array*                  toByteArr   (PopplerByteArrayPtr        p) noexcept { return reinterpret_cast<poppler::byte_array*>(p); }
static inline PopplerEmbeddedFileListPtr            fromFileList(std::vector<poppler::embedded_file*>* p) noexcept { return reinterpret_cast<PopplerEmbeddedFileListPtr>(p); }
static inline PopplerByteArrayPtr                   fromByteArr (poppler::byte_array* p) noexcept { return reinterpret_cast<PopplerByteArrayPtr>(p); }

// Destinations
static inline std::map<std::string,poppler::destination>*                toDestMap (PopplerDestinationMapPtr  p) noexcept { return reinterpret_cast<std::map<std::string,poppler::destination>*>(p); }
static inline std::vector<std::pair<std::string,poppler::destination*>>* toDestList(PopplerDestinationListPtr p) noexcept { return reinterpret_cast<std::vector<std::pair<std::string,poppler::destination*>>*>(p); }
static inline poppler::destination*                                      toDest    (PopplerDestinationPtr     p) noexcept { return reinterpret_cast<poppler::destination*>(p); }
static inline PopplerDestinationMapPtr  fromDestMap (std::map<std::string,poppler::destination>* p) noexcept { return reinterpret_cast<PopplerDestinationMapPtr>(p); }
static inline PopplerDestinationListPtr fromDestList(std::vector<std::pair<std::string,poppler::destination*>>* p) noexcept { return reinterpret_cast<PopplerDestinationListPtr>(p); }

// Fonts
static inline poppler::font_iterator*           toFontIter  (PopplerFontIteratorPtr p) noexcept { return reinterpret_cast<poppler::font_iterator*>(p); }
static inline std::vector<poppler::font_info>*  toFontList  (PopplerFontInfoListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::font_info>*>(p); }
static inline poppler::font_info*               toFont      (PopplerFontInfoPtr     p) noexcept { return reinterpret_cast<poppler::font_info*>(p); }
static inline PopplerFontIteratorPtr            fromFontIter(poppler::font_iterator*          p) noexcept { return reinterpret_cast<PopplerFontIteratorPtr>(p); }
static inline PopplerFontInfoListPtr            fromFontList(std::vector<poppler::font_info>* p) noexcept { return reinterpret_cast<PopplerFontInfoListPtr>(p); }

// Page transitions
static inline poppler::page_transition*  toTransition  (PopplerPageTransitionPtr p) noexcept { return reinterpret_cast<poppler::page_transition*>(p); }
static inline PopplerPageTransitionPtr   fromTransition(poppler::page_transition* p) noexcept { return reinterpret_cast<PopplerPageTransitionPtr>(p); }

// String list
static inline std::vector<std::string>*  toStrList  (PopplerStringListPtr p) noexcept { return reinterpret_cast<std::vector<std::string>*>(p); }
static inline PopplerStringListPtr       fromStrList(std::vector<std::string>* p) noexcept { return reinterpret_cast<PopplerStringListPtr>(p); }

#endif // __cplusplus

// MARK: - Document Loading

inline PopplerDocPtr poppler_document_load_from_file(const char* file_name) {
    return fromDoc(poppler::document::load_from_file(file_name));
}

inline PopplerDocPtr poppler_document_load_from_raw_data(const char* file_data, int length) {
    return fromDoc(poppler::document::load_from_raw_data(file_data, length));
}

inline void poppler_delete_document(PopplerDocPtr doc) {
    delete toDoc(doc);
}

inline int poppler_document_get_pages(PopplerDocPtr doc) {
    return toDoc(doc)->pages();
}

inline PopplerPagePtr poppler_document_create_page(PopplerDocPtr doc, int index) {
    return fromPage(toDoc(doc)->create_page(index));
}

inline void poppler_delete_page(PopplerPagePtr page) {
    delete toPage(page);
}

inline std::string poppler_page_text_utf8(PopplerPagePtr page) {
    poppler::ustring ustr = toPage(page)->text();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

// MARK: - Document Metadata

inline std::string poppler_document_get_title(PopplerDocPtr doc) {
    poppler::ustring ustr = toDoc(doc)->get_title();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline std::string poppler_document_get_author(PopplerDocPtr doc) {
    poppler::ustring ustr = toDoc(doc)->get_author();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline long poppler_document_get_creation_date(PopplerDocPtr doc) {
    return static_cast<long>(toDoc(doc)->get_creation_date_t());
}

// MARK: - Text Boxes & Layout

inline PopplerTextBoxListPtr poppler_page_get_text_list(PopplerPagePtr page) {
    // text_list returns std::vector by value. We move it to the heap.
    // Use text_list_include_font (1) to ensure font information is extracted.
    auto list = new std::vector<poppler::text_box>(toPage(page)->text_list(poppler::page::text_list_include_font));
    return fromTextList(list);
}

inline void poppler_delete_text_list(PopplerTextBoxListPtr list) {
    delete toTextList(list);
}

inline int poppler_text_list_get_size(PopplerTextBoxListPtr list) {
    return toTextList(list)->size();
}

inline PopplerTextBoxPtr poppler_text_list_get_item(PopplerTextBoxListPtr list, int index) {
    auto& vec = *toTextList(list);
    return reinterpret_cast<PopplerTextBoxPtr>(&vec[index]);
}

inline std::string poppler_text_box_get_text_utf8(PopplerTextBoxPtr box) {
    poppler::ustring ustr = toTextBox(box)->text();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}

inline PopplerRect poppler_text_box_get_bbox(PopplerTextBoxPtr box) {
    poppler::rectf r = toTextBox(box)->bbox();
    return { r.left(), r.top(), r.right(), r.bottom() };
}

inline double poppler_text_box_get_font_size(PopplerTextBoxPtr box) {
    return toTextBox(box)->get_font_size();
}

inline std::string poppler_text_box_get_font_name(PopplerTextBoxPtr box) {
    return toTextBox(box)->get_font_name();
}

inline int poppler_text_box_get_rotation(PopplerTextBoxPtr box) {
    return toTextBox(box)->rotation();
}

inline bool poppler_text_box_has_space_after(PopplerTextBoxPtr box) {
    return toTextBox(box)->has_space_after();
}

inline bool poppler_text_box_has_font_info(PopplerTextBoxPtr box) {
    return toTextBox(box)->has_font_info();
}

// MARK: - Image Rendering

inline PopplerRendererPtr poppler_renderer_create() {
    return fromRenderer(new poppler::page_renderer());
}
inline void poppler_renderer_delete(PopplerRendererPtr renderer) {
    delete toRenderer(renderer);
}
inline void poppler_renderer_set_render_hint(PopplerRendererPtr renderer, int hint, bool on) {
    toRenderer(renderer)->set_render_hint(static_cast<poppler::page_renderer::render_hint>(hint), on);
}
inline PopplerImagePtr poppler_renderer_render_page(PopplerRendererPtr renderer, PopplerPagePtr page, double xres, double yres) {
    // page_renderer returns poppler::image by value, we move it to the heap.
    poppler::image img = toRenderer(renderer)->render_page(toPage(page), xres, yres);
    return fromImage(new poppler::image(img));
}

inline void poppler_image_delete(PopplerImagePtr image) {
    delete toImage(image);
}
inline bool poppler_image_is_valid(PopplerImagePtr image) {
    return toImage(image)->is_valid();
}
inline int poppler_image_get_width(PopplerImagePtr image) {
    return toImage(image)->width();
}
inline int poppler_image_get_height(PopplerImagePtr image) {
    return toImage(image)->height();
}
inline int poppler_image_get_bytes_per_row(PopplerImagePtr image) {
    return toImage(image)->bytes_per_row();
}
inline const char* poppler_image_get_data(PopplerImagePtr image) {
    return toImage(image)->const_data();
}
inline int poppler_image_get_format(PopplerImagePtr image) {
    return static_cast<int>(toImage(image)->format());
}

// MARK: - Table of Contents (TOC)

inline PopplerTOCPtr poppler_document_create_toc(PopplerDocPtr doc) {
    poppler::toc* t = toDoc(doc)->create_toc();
    return fromTOC(t); // Can be null
}
inline void poppler_delete_toc(PopplerTOCPtr toc) {
    delete toTOC(toc);
}
inline PopplerTOCItemPtr poppler_toc_get_root(PopplerTOCPtr toc) {
    return reinterpret_cast<PopplerTOCItemPtr>(toTOC(toc)->root());
}
inline std::string poppler_toc_item_get_title(PopplerTOCItemPtr item) {
    poppler::ustring ustr = toTOCItem(item)->title();
    poppler::byte_array bytes = ustr.to_utf8();
    return std::string(bytes.begin(), bytes.end());
}
inline bool poppler_toc_item_is_open(PopplerTOCItemPtr item) {
    return toTOCItem(item)->is_open();
}
inline PopplerTOCItemListPtr poppler_toc_item_get_children(PopplerTOCItemPtr item) {
    auto list = new std::vector<poppler::toc_item*>(toTOCItem(item)->children());
    return fromTOCList(list);
}
inline void poppler_delete_toc_item_list(PopplerTOCItemListPtr list) {
    delete toTOCList(list);
}
inline int poppler_toc_item_list_get_size(PopplerTOCItemListPtr list) {
    return toTOCList(list)->size();
}
inline PopplerTOCItemPtr poppler_toc_item_list_get_item(PopplerTOCItemListPtr list, int index) {
    auto& vec = *toTOCList(list);
    return reinterpret_cast<PopplerTOCItemPtr>(vec[index]);
}

// MARK: - Embedded Files

inline PopplerEmbeddedFileListPtr poppler_document_get_embedded_files(PopplerDocPtr doc) {
    auto list = new std::vector<poppler::embedded_file*>(toDoc(doc)->embedded_files());
    return fromFileList(list);
}
inline void poppler_delete_embedded_file_list(PopplerEmbeddedFileListPtr list) {
    auto vec = toFileList(list);
    for (auto f : *vec) { delete f; }
    delete vec;
}
inline int poppler_embedded_file_list_get_size(PopplerEmbeddedFileListPtr list) {
    return toFileList(list)->size();
}
inline PopplerEmbeddedFilePtr poppler_embedded_file_list_get_item(PopplerEmbeddedFileListPtr list, int index) {
    auto& vec = *toFileList(list);
    return reinterpret_cast<PopplerEmbeddedFilePtr>(vec[index]);
}
inline std::string poppler_embedded_file_get_name(PopplerEmbeddedFilePtr file) {
    // name() returns std::string directly in the poppler-cpp wrapper.
    // unicodeName() is a GLib/Qt API and does not exist in poppler-cpp.
    return toFile(file)->name();
}
inline std::string poppler_embedded_file_get_mime_type(PopplerEmbeddedFilePtr file) {
    return toFile(file)->mime_type();
}
inline int poppler_embedded_file_get_size(PopplerEmbeddedFilePtr file) {
    return toFile(file)->size();
}
inline PopplerByteArrayPtr poppler_embedded_file_get_data(PopplerEmbeddedFilePtr file) {
    auto arr = new poppler::byte_array(toFile(file)->data());
    return fromByteArr(arr);
}
inline void poppler_delete_byte_array(PopplerByteArrayPtr arr) {
    delete toByteArr(arr);
}
inline const char* poppler_byte_array_get_data(PopplerByteArrayPtr arr) {
    return toByteArr(arr)->data();
}
inline int poppler_byte_array_get_size(PopplerByteArrayPtr arr) {
    return toByteArr(arr)->size();
}

// MARK: - Destinations

inline PopplerDestinationMapPtr poppler_document_create_destination_map(PopplerDocPtr doc) {
    auto m = new std::map<std::string, poppler::destination>(toDoc(doc)->create_destination_map());
    return fromDestMap(m);
}
inline void poppler_delete_destination_map(PopplerDestinationMapPtr map) {
    delete toDestMap(map);
}
inline PopplerDestinationListPtr poppler_destination_map_to_list(PopplerDestinationMapPtr map) {
    auto vec = new std::vector<std::pair<std::string, poppler::destination*>>();
    for (auto& pair : *toDestMap(map)) {
        vec->push_back({pair.first, &pair.second});
    }
    return fromDestList(vec);
}
inline void poppler_delete_destination_list(PopplerDestinationListPtr list) {
    delete toDestList(list);
}
inline int poppler_destination_list_get_size(PopplerDestinationListPtr list) {
    return toDestList(list)->size();
}
inline const char* poppler_destination_list_get_name(PopplerDestinationListPtr list, int index) {
    return (*toDestList(list))[index].first.c_str();
}
inline PopplerDestinationPtr poppler_destination_list_get_dest(PopplerDestinationListPtr list, int index) {
    return reinterpret_cast<PopplerDestinationPtr>((*toDestList(list))[index].second);
}
inline int poppler_destination_get_page_number(PopplerDestinationPtr dest) {
    return toDest(dest)->page_number();
}
inline double poppler_destination_get_left(PopplerDestinationPtr dest) {
    return toDest(dest)->left();
}
inline double poppler_destination_get_top(PopplerDestinationPtr dest) {
    return toDest(dest)->top();
}
inline double poppler_destination_get_zoom(PopplerDestinationPtr dest) {
    return toDest(dest)->zoom();
}

// MARK: - Fonts

inline PopplerFontIteratorPtr poppler_document_create_font_iterator(PopplerDocPtr doc, int start_page) {
    return fromFontIter(toDoc(doc)->create_font_iterator(start_page));
}
inline void poppler_delete_font_iterator(PopplerFontIteratorPtr iter) {
    delete toFontIter(iter);
}
inline bool poppler_font_iterator_has_next(PopplerFontIteratorPtr iter) {
    return toFontIter(iter)->has_next();
}
inline PopplerFontInfoListPtr poppler_font_iterator_next(PopplerFontIteratorPtr iter) {
    auto vec = new std::vector<poppler::font_info>(toFontIter(iter)->next());
    return fromFontList(vec);
}
inline void poppler_delete_font_info_list(PopplerFontInfoListPtr list) {
    delete toFontList(list);
}
inline int poppler_font_info_list_get_size(PopplerFontInfoListPtr list) {
    return toFontList(list)->size();
}
inline PopplerFontInfoPtr poppler_font_info_list_get_item(PopplerFontInfoListPtr list, int index) {
    return reinterpret_cast<PopplerFontInfoPtr>(&(*toFontList(list))[index]);
}
inline std::string poppler_font_info_get_name(PopplerFontInfoPtr font) {
    return toFont(font)->name();
}
inline std::string poppler_font_info_get_file(PopplerFontInfoPtr font) {
    return toFont(font)->file();
}
inline bool poppler_font_info_is_embedded(PopplerFontInfoPtr font) {
    return toFont(font)->is_embedded();
}

// MARK: - Page Transitions

inline PopplerPageTransitionPtr poppler_page_get_transition(PopplerPagePtr page) {
    poppler::page_transition* t = toPage(page)->transition();
    return fromTransition(t); // can be null
}
inline void poppler_delete_page_transition(PopplerPageTransitionPtr transition) {
    delete toTransition(transition);
}
inline int poppler_page_transition_get_type(PopplerPageTransitionPtr transition) {
    return static_cast<int>(toTransition(transition)->type());
}
inline double poppler_page_transition_get_duration(PopplerPageTransitionPtr transition) {
    return toTransition(transition)->durationReal();
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
    return fromDoc(poppler::document::load_from_file(
        std::string(file_name),
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    ));
}

inline PopplerDocPtr poppler_document_load_from_raw_data_with_password(
    const char* file_data,
    int         length,
    const char* owner_password,
    const char* user_password)
{
    if (!file_data || length <= 0) return nullptr;
    return fromDoc(poppler::document::load_from_raw_data(
        file_data, length,
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Extended Document Metadata
// ─────────────────────────────────────────────────────────────────────────────

inline std::string poppler_document_get_subject(PopplerDocPtr doc) {
    poppler::ustring u = toDoc(doc)->get_subject();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_keywords(PopplerDocPtr doc) {
    poppler::ustring u = toDoc(doc)->get_keywords();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_creator(PopplerDocPtr doc) {
    poppler::ustring u = toDoc(doc)->get_creator();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline std::string poppler_document_get_producer(PopplerDocPtr doc) {
    poppler::ustring u = toDoc(doc)->get_producer();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline long poppler_document_get_modification_date(PopplerDocPtr doc) {
    return static_cast<long>(toDoc(doc)->get_modification_date_t());
}

inline bool poppler_document_is_encrypted(PopplerDocPtr doc) {
    return toDoc(doc)->is_encrypted();
}

inline bool poppler_document_is_locked(PopplerDocPtr doc) {
    return toDoc(doc)->is_locked();
}

inline int poppler_document_get_page_layout(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->page_layout());
}

inline int poppler_document_get_page_mode(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->page_mode());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Dimensions
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the media box of a page in PDF points (1 pt = 1/72 inch).
/// Explicitly passes poppler::media_box — the no-arg default is crop_box.
inline PopplerRect poppler_page_get_media_box(PopplerPagePtr page) {
    poppler::rectf r = toPage(page)->page_rect(poppler::media_box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

/// Returns any of the five PDF page boxes.
/// box_type: 0=media_box, 1=crop_box, 2=bleed_box, 3=trim_box, 4=art_box
inline PopplerRect poppler_page_get_page_rect(PopplerPagePtr page, int box_type) {
    auto box = static_cast<poppler::page_box_enum>(box_type);
    poppler::rectf r = toPage(page)->page_rect(box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Extraction with Layout
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts the full text of a page using an explicit layout algorithm.
/// @param layout  0 = physical_layout, 1 = raw_order_layout, 2 = non_raw_non_physical_layout (poppler >= 0.88)
/// Uses text(page_rect(), layout_mode) for maximum version compatibility (available since poppler 0.16).
inline std::string poppler_page_text_utf8_with_layout(PopplerPagePtr page, int layout) {
    auto* p    = toPage(page);
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
    return toImage(image)->save(
        std::string(file_path), std::string(format), dpi);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Typed Render-Hint Setters
// Avoids exposing magic integers to the Swift layer.
// ─────────────────────────────────────────────────────────────────────────────

inline void poppler_renderer_set_antialiasing(PopplerRendererPtr r, bool on) {
    toRenderer(r)->set_render_hint(
        poppler::page_renderer::antialiasing, on);
}

inline void poppler_renderer_set_text_antialiasing(PopplerRendererPtr r, bool on) {
    toRenderer(r)->set_render_hint(
        poppler::page_renderer::text_antialiasing, on);
}

inline void poppler_renderer_set_text_hinting(PopplerRendererPtr r, bool on) {
    toRenderer(r)->set_render_hint(
        poppler::page_renderer::text_hinting, on);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PDF Version
// ─────────────────────────────────────────────────────────────────────────────

inline void poppler_document_get_pdf_version(PopplerDocPtr doc, int* major, int* minor) {
    toDoc(doc)->get_pdf_version(major, minor);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document State
// ─────────────────────────────────────────────────────────────────────────────

inline bool poppler_document_is_linearized(PopplerDocPtr doc) {
    return toDoc(doc)->is_linearized();
}

inline bool poppler_document_has_embedded_files(PopplerDocPtr doc) {
    return toDoc(doc)->has_embedded_files();
}

/// Attempts to unlock an encrypted document after load.
/// Returns true if the document is now unlocked.
inline bool poppler_document_unlock(
    PopplerDocPtr doc,
    const char*   owner_password,
    const char*   user_password)
{
    return toDoc(doc)->unlock(
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Label, Orientation & Duration
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the logical page label (e.g. "iii", "iv", "1") as UTF-8.
inline std::string poppler_page_get_label(PopplerPagePtr page) {
    poppler::ustring u = toPage(page)->label();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

/// Returns the page orientation: 0=landscape, 1=portrait, 2=seascape, 3=upside_down.
inline int poppler_page_get_orientation(PopplerPagePtr page) {
    return static_cast<int>(toPage(page)->orientation());
}

/// Returns the presentation slide duration in seconds, or -1 if not set.
inline double poppler_page_get_duration(PopplerPagePtr page) {
    return toPage(page)->duration();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Region Text Extraction
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts text within a rectangle (in PDF points) using the library default layout.
inline std::string poppler_page_text_in_rect(
    PopplerPagePtr page,
    double left, double top, double right, double bottom)
{
    auto* p = toPage(page);
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
    auto* p    = toPage(page);
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
    auto* p = toPage(page);
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
    return static_cast<int>(toDest(dest)->type());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Font Info Extensions
// ─────────────────────────────────────────────────────────────────────────────

/// Returns font type: unknown=0, type1=1, type1c=2, type1_cot=3, type3=4,
///   truetype=5, truetype_ot=6, cid_type0=7, cid_type0c=8, cid_type0c_ot=9,
///   cid_type2=10, cid_type2_ot=11.
inline int poppler_font_info_get_type(PopplerFontInfoPtr font) {
    return static_cast<int>(toFont(font)->type());
}

/// Returns true if the font is embedded as a subset (only glyphs used are present).
inline bool poppler_font_info_is_subset(PopplerFontInfoPtr font) {
    return toFont(font)->is_subset();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Embedded File Extensions
// ─────────────────────────────────────────────────────────────────────────────

inline bool poppler_embedded_file_is_valid(PopplerEmbeddedFilePtr file) {
    return toFile(file)->is_valid();
}

inline std::string poppler_embedded_file_get_description(PopplerEmbeddedFilePtr file) {
    poppler::ustring u = toFile(file)->description();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

inline long poppler_embedded_file_get_creation_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(toFile(file)->creation_date_t());
}

inline long poppler_embedded_file_get_modification_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(toFile(file)->modification_date_t());
}

/// Returns the file checksum as a lowercase hex string (empty if unavailable).
inline std::string poppler_embedded_file_get_checksum(PopplerEmbeddedFilePtr file) {
    // checksum() returns poppler::byte_array (std::vector<char>), not std::string
    poppler::byte_array raw = toFile(file)->checksum();
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
    return static_cast<int>(toTransition(t)->alignment());
}

/// Motion direction: 0=inward (toward center), 1=outward (toward edges).
inline int poppler_page_transition_get_motion_direction(PopplerPageTransitionPtr t) {
    return static_cast<int>(toTransition(t)->direction());
}

/// Direction of motion in degrees (e.g. 0=left-to-right, 90=bottom-to-top).
inline int poppler_page_transition_get_angle(PopplerPageTransitionPtr t) {
    return static_cast<int>(toTransition(t)->angle());
}

/// Scale factor for fly transitions (0.0-1.0).
inline double poppler_page_transition_get_scale(PopplerPageTransitionPtr t) {
    return toTransition(t)->scale();
}

/// Whether the transition uses a rectangular rather than circular region.
inline bool poppler_page_transition_is_rectangular(PopplerPageTransitionPtr t) {
    return toTransition(t)->is_rectangular();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Permissions
// ─────────────────────────────────────────────────────────────────────────────

/// Checks a single permission flag.
/// perm values (poppler::permission_enum):
///   0=perm_print, 1=perm_change, 2=perm_copy, 3=perm_add_notes,
///   4=perm_fill_forms, 5=perm_accessibility, 6=perm_assemble, 7=perm_print_high_resolution
inline bool poppler_document_has_permission(PopplerDocPtr doc, int perm) {
    return toDoc(doc)->has_permission(
        static_cast<poppler::permission_enum>(perm));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Form Type & JavaScript
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the form type: 0=none, 1=acro (AcroForms), 2=xfa (Adobe XFA).
/// form_type is an enum class inside poppler::document.
inline int poppler_document_get_form_type(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->form_type());
}

/// Returns true if the document contains embedded JavaScript.
inline bool poppler_document_has_javascript(PopplerDocPtr doc) {
    return toDoc(doc)->has_javascript();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - XMP Metadata & PDF ID
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the raw XMP metadata packet as a UTF-8 string (empty if absent).
inline std::string poppler_document_get_metadata(PopplerDocPtr doc) {
    poppler::ustring u = toDoc(doc)->metadata();
    poppler::byte_array b = u.to_utf8();
    return std::string(b.begin(), b.end());
}

/// Returns true if get_pdf_id() produced a non-empty result.
inline bool poppler_document_has_pdf_id(PopplerDocPtr doc) {
    std::string p, u;
    return toDoc(doc)->get_pdf_id(&p, &u);
}

/// Returns the permanent PDF document identifier (hex string).
inline std::string poppler_document_get_permanent_id(PopplerDocPtr doc) {
    std::string p, u;
    toDoc(doc)->get_pdf_id(&p, &u);
    return p;
}

/// Returns the update PDF document identifier (hex string, changes on each save).
inline std::string poppler_document_get_update_id(PopplerDocPtr doc) {
    std::string p, u;
    toDoc(doc)->get_pdf_id(&p, &u);
    return u;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Info Dictionary (custom metadata keys)
// ─────────────────────────────────────────────────────────────────────────────

inline PopplerStringListPtr poppler_document_get_info_keys(PopplerDocPtr doc) {
    auto vec = new std::vector<std::string>(
        toDoc(doc)->info_keys());
    return fromStrList(vec);
}

inline void poppler_delete_string_list(PopplerStringListPtr list) {
    delete toStrList(list);
}

inline int poppler_string_list_get_size(PopplerStringListPtr list) {
    return static_cast<int>(
        toStrList(list)->size());
}

inline std::string poppler_string_list_get_item(PopplerStringListPtr list, int index) {
    return (*toStrList(list))[index];
}

/// Returns the UTF-8 value for an arbitrary info-dictionary key (empty if absent).
inline std::string poppler_document_get_info_key(PopplerDocPtr doc, const char* key) {
    if (!key) return {};
    poppler::ustring uval = toDoc(doc)->info_key(std::string(key));
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
    return fromPage(toDoc(doc)->create_page(ulabel));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Persistence
// ─────────────────────────────────────────────────────────────────────────────

/// Saves the document (with any in-memory modifications) to a file.
inline bool poppler_document_save(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return toDoc(doc)->save(std::string(file_path));
}

/// Saves an unmodified byte-for-byte copy of the document to a file.
inline bool poppler_document_save_a_copy(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return toDoc(doc)->save_a_copy(std::string(file_path));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Box: Character Bounding Boxes & Writing Mode
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the number of UCS4 code points in the text box's text.
inline int poppler_text_box_get_text_length(PopplerTextBoxPtr box) {
    return static_cast<int>(
        toTextBox(box)->text().size());
}

/// Returns the bounding box for the i-th glyph (in PDF points).
/// Returns {0,0,0,0} for out-of-range indices.
inline PopplerRect poppler_text_box_get_char_bbox(PopplerTextBoxPtr box, int index) {
    poppler::rectf r = toTextBox(box)->char_bbox(
        static_cast<size_t>(index));
    return { r.left(), r.top(), r.right(), r.bottom() };
}

/// Returns the writing mode for the i-th glyph.
/// writing_mode_enum is a nested type of text_box: invalid=-1, horizontal=0, vertical=1.
inline int poppler_text_box_get_wmode(PopplerTextBoxPtr box, int index) {
    return static_cast<int>(
        toTextBox(box)->get_wmode(index));
}
