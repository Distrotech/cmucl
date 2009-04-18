;;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Package: STREAM -*-
;;;
;;; **********************************************************************
;;; This code was written by Paul Foley and has been placed in the public
;;; domain.
;;;
(ext:file-comment "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/pcl/simple-streams/external-formats/cp1250.lisp,v 1.1.2.2 2009/03/28 13:40:40 rtoy Exp $")

(in-package "STREAM")

(defconstant +ms-cp1250+
  (make-array 128 :element-type '(unsigned-byte 16)
     :initial-contents #(8364 65534 8218 65534 8222 8230 8224 8225 65534 8240
                         352 8249 346 356 381 377 65534 8216 8217 8220 8221
                         8226 8211 8212 65534 8482 353 8250 347 357 382 378 160
                         711 728 321 164 260 166 167 168 169 350 171 172 173
                         174 379 176 177 731 322 180 181 182 183 184 261 351
                         187 317 733 318 380 340 193 194 258 196 313 262 199
                         268 201 280 203 282 205 206 270 272 323 327 211 212
                         336 214 215 344 366 218 368 220 221 354 223 341 225
                         226 259 228 314 263 231 269 233 281 235 283 237 238
                         271 273 324 328 243 244 337 246 247 345 367 250 369
                         252 253 355 729)))

(define-external-format :cp1250 (:mac-roman)
  ((table +ms-cp1250+)))