(require 'cl)
(require 'recur)
(require 'functional)
(provide 'streams)

(defstruct stream head future)
(defun stream (hd &optional future)
  (make-stream :head hd :future future))

(defun scar (stream)
  (cond ((not stream) nil)
		(t 
		 (progn
		   (if (not (stream-p stream))
			   (error "Tried to take the scar of a non-stream %S." stream))
		   (stream-head stream)))))

(defun scdr (stream)
  (cond ((not stream) nil)
		(t
		 (progn
		   (if (not (stream-p stream))
			   (error "Tried to take the scdr of a non-stream %S." stream))
		   (let ((fut (stream-future stream)))
			 (if fut
				 (progn 
				   (if (not (functionp fut)) (error "The future of a stream must be either nil or a function.  Instead its %S" fut))
				   (let ((fut (funcall fut)))
					 (if (not (stream-p fut)) (error "The future of a stream must evaluate to a stream.  Instead it was %S" fut))
					 fut))
			   nil))))))

(defun stream? (object)
  (or (not object)
	  (stream-p object)))

(defun stream-future-nil? (object)
  (nil? (stream-future object)))
(defun stream-with-future? (object)
  (not (nil? (stream-future object))))

(eval-when-compile-also 
 (defmacro stream-case (stream
						nil-case
						=a=expressions
						=a-f=expressions)
   (with-gensyms 
	(stream%)
	`(let ((,stream% ,stream))
	   (if (not (stream? ,stream%)) (error "Stream-case needs a stream input, got instead %S." ,stream%))
	   (cond 
		((nil? ,stream%)
		 ,@nil-case)
		((stream-future-nil? ,stream%)
		 (let ((,(car (car =a=expressions)) (scar ,stream%)))
		   ,@(cdr =a=expressions)))
		((stream-with-future? ,stream%)
		 (let ((,(car (car =a-f=expressions)) (scar ,stream%))
			   (,(cadr (car =a-f=expressions)) (stream-future ,stream%)))
		   ,@(cdr =a-f=expressions)))
		(t (error "Couldn't figure out what to do with stream %S.  This should never happen." stream%))))))

 (defmacro lex-stream-case (stream
							nil-case
							=a=expressions
							=a-f=expressions)
   (with-gensyms 
	(stream%)
	`(let ((,stream% ,stream))
	   (if (not (stream? ,stream%)) (error "Stream-case needs a stream input, got instead %S." ,stream%))
	   (cond 
		((nil? ,stream%)
		 ,@nil-case)
		((stream-future-nil? ,stream%)
		 (lexical-let ((,(car (car =a=expressions)) (scar ,stream%)))
		   ,@(cdr =a=expressions)))
		((stream-with-future? ,stream%)
		 (lexical-let ((,(car (car =a-f=expressions)) (scar ,stream%))
					   (,(cadr (car =a-f=expressions)) (stream-future ,stream%)))
		   ,@(cdr =a-f=expressions)))
		(t (error "Couldn't figure out what to do with stream %S.  This should never happen." stream%))))))

 )

(recur-defun* take-n (stream n &optional acc)
  (if (= n 0) (reverse acc)
	(stream-case stream
				 (reverse acc)
				 ((a) (reverse (cons a acc)))
				 ((a f) (recur (funcall f) (- n 1) (cons a acc))))))


(defun smapcar (f stream)
  (stream-case stream
			   nil
			   ((a) (stream (funcall f a) nil))
			   ((a future) 
				(lexical-let ((future future)
							  (f f))
				  (stream (funcall f a) 
						  (lambda () (smapcar f (funcall future))))))))

(defun smapcar2 (f-of-2 stream1 stream2)
  (stream-case stream1
			   nil
			   ((a) (stream-case stream2
								 nil
								 ((b) (stream (funcall f-of-2 a b) nil))
								 ((b g)
								  (stream (funcall f-of-2 a b) nil))))
			   ((a f)
				(stream-case stream2 
							 nil
							 ((b) (stream (funcall f-of-2 a b) nil))
							 ((b g)
							  (lexical-let ((f-of-2 f-of-2)
											(f f)
											(g g))
								(stream (funcall f-of-2 a b) 
										(lambda () (smapcar2 f-of-2 (funcall f) (funcall g))))))))))


(defvar ones (stream 1 (lambda () ones)))

(defun ints-from (n)
  (lexical-let ((n n))
	(stream n (lambda () (ints-from (+ n 1))))))

(defun ints-down-from (n)
  (lexical-let ((n n))
	(stream n (lambda () (ints-down-from (- n 1))))))

(defun forever (value)
  (lexical-let ((value value))
	(stream value (lambda () (forever value)))))

(defun combine-by-call (f-stream arg-stream)
  (smapcar2 #'funcall f-stream arg-stream))

(defun combine-by-partial-right (f-stream arg-stream)
  (smapcar2 #'par f-stream arg-stream))

(defun smapcar* (f &rest streams)
  (recur-let ((partial-stream (combine-by-partial-right (forever f) (car streams)))
			  (rest (cdr streams)))
			 (if (= (length rest) 0) (smapcar #'funcall partial-stream)
			   (recur (combine-by-partial-right partial-stream (car rest))
					  (cdr rest)))))

(defun repeating (seq)
  (lexical-let ((seq seq))
	(stream (car seq) (lambda ()
						(repeating (suffix (cdr seq) (car seq)))))))

(defun* random-numbers (lim &optional (state (make-random-state)))
  (let* ((*random-state* state)
		 (val (random* lim)))
	(lexical-let ((new-state (make-random-state))
				  (lim lim))
	  (stream val (lambda () 
					(random-numbers lim new-state))))))

(defvar fibs (stream 1
					 (lambda () 
					   (stream 1 
							   (lambda () (smapcar2 #'+ fibs (scdr fibs))))))
  "The stream of fibonocci numbers")

(defun stream-cat (stream1 stream2)
  (stream-case 
   stream1
   stream2
   ((a) (stream-case stream2 
					 (stream a nil)
					 ((b) (stream a (lexical-let ((b b)) 
									  (lambda () (stream b nil)))))
					 ((b g)
					  (stream a (lexical-let ((b b)
											  (g g))
								  (lambda () (stream b g)))))))
   ((a f)
	(stream-case stream2
				 (stream a f)
				 ((b) (stream a 
							  (lexical-let ((f f)
											(stream2 stream2))
								(lambda () (stream-cat (funcall f) stream2)))))
				 ((b g) 
				  (stream a 
						  (lexical-let ((f f)
										(stream2 stream2))
							(lambda () (stream-cat (funcall f) stream2)))))))))

(defun stream-interleave (stream1 stream2)
  (stream-case
   stream1
   stream2
   ((a) (stream-case stream2
					 (stream a nil)
					 ((b) (stream a (lexical-let ((b b)) (lambda () (stream b nil)))))
					 ((b g) (stream a 
									(lexical-let ((b b)
												  (g g))
									  (lambda () (stream b g)))))))
   ((a f)
	(stream-case stream2
				 (stream a f)
				 ((b) (stream a
							  (lexical-let ((b b)
											(f f))
								(lambda () (stream b f)))))
				 ((b g)
				  (stream a
						  (lexical-let ((b b)
										(g g)
										(f f))
							(lambda ()
							  (stream-interleave 
							   (stream b g) (funcall f))))))))))

(recur-defun* stream-map-cat (mf stream)
  (lexical-let ((mf mf))
	(stream-case stream
				 nil
				 ((a) (funcall mf a))
				 ((a f) 
				  (lexical-let ((interior-stream (funcall mf a))
								(f f))
					(stream-case 
 					 interior-stream
					 (recur mf (funcall f))
					 ((b) (stream b 
								  (delay
								   (stream-map-cat mf (funcall f)))))
					 ((b g) (stream b
									(lexical-let ((g g))
									  (delay 
									   (stream-cat (funcall g)
												   (stream-map-cat mf (funcall f)))))))))))))





(defmacro delay (&rest body)
  `(lambda () ,@body))

(defmacro delay-stream (a &rest body)
  `(stream ,a (delay ,@body)))


(defun stream-bind (v f)
  (stream-map-cat f v))
(defun stream-return (x)
  (stream x nil))

(setq monad-stream 
  (tbl! :m-bind #'stream-bind
		:m-return #'stream-return
		:m-zero nil))

(setq normal-numbers 
	  (mlet**_ monad-stream ((u (random-numbers 1.0))
				(v (random-numbers 1.0 (make-random-state t))))
			   (lexical-let ((r (sqrt (* -2 (log  u))))
							 (s (* 2 pi v)))
				 (stream (* r (cos s))
						 (delay (stream (* r (sin s)) nil))))))


